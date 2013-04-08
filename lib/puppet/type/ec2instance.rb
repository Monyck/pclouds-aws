require 'rubygems'
require 'facter'
require 'fog'
require 'yaml'

Puppet::Type.newtype(:ec2instance) do
	@doc = "Manage EC2 Instances"

	# Allow to be ensurable
	ensurable

	newparam(:name) do
		desc "The friendly Name (tag) of the EC2 Instance"
		isnamevar
		isrequired
	end

	# AvailabilityZone and Region - we need to determine which aws region we need to communicate with.
	# The user can specify either the availability zone or a region. If they specify an availability zone
	# then we will calculate the region from that.
	newparam(:availability_zone) do
		desc "The availability zone that the instance should run in"
	end

	# If the user does not select a specific availability zone then they can choose a region and the instance
	# will be started in any of the availability zones in that region.  If no region is specified then we
	# will automatically choose the same region as the server owning the ec2instance resource (the one 
	# performing the puppet run)
	newparam(:region) do
		desc "The region that this instance belongs."
		defaultto do
			resource[:availability_zone] ? resource[:availability_zone].gsub(/.$/,'') : Facter.value('ec2_placement_availability_zone').gsub(/.$/,'')
		end
		validate do |value|
			if (resource[:availability_zone] && resource[:availability_zone].gsub(/.$/,'') != value)
				raise ArgumentError , "ec2instance: Sorry, availability_zone #{resource[:availability_zone]} is in region #{resource[:availability_zone].gsub(/.$/,'')}.  Please leave the 'region' blank or correct it."
			end
		end
	end

	newparam(:instance_type) do
		valid_types = [ 't1.micro','m1.small','m1.medium','m1.large','m1.xlarge','m3.xlarge','m3.2xlarge','c1.medium','c1.xlarge','m2.xlargei','m2.2xlarge','m2.4xlarge','cr1.8xlarge','hi1.4xlarge','hs1.8xlarge','cc1.4xlarge','cc2.8xlarge','cg1.4xlarge' ]
		desc "The instance type: Valid values are: #{valid_types.join(', ')}"
		defaultto 'm1.small'
		validate do |value|
			unless valid_types.include?(value)
				raise ArgumentError , "ec2instance: #{value} is not valid instance_type"
			end
		end
	end

	newparam(:image_id) do
		desc "The image_id for the AMI to boot from"
		isrequired
		validate do |value|
			unless value =~ /^ami-/
				raise ArgumentError , "ec2instance: #{value} is not valid image_id which start 'ami-'"
			end
		end
	end

	newparam(:min_count) do
		desc "The minimum number of instances to launch."
		defaultto '1'
		validate do |value|
			unless value =~ /^[0-9]+$/
				raise ArgumentError , "ec2instance: #{value} is not a valid, min_count needs to be an integer."
			end
		end
	end

	newparam(:max_count) do
		desc "The maximum number of instances to launch."
		defaultto '1'
		validate do |value|
			unless value =~ /^[0-9]+$/
				raise ArgumentError , "ec2instance: #{value} is not a valid, max_count needs to be an integer."
			end
		end
	end

	newparam(:key_name) do
		desc "The name of the key pair to use."
	end

	newparam(:security_group_names) do
		desc "A comma separated list of security groups by Name that you want the instance to join."
	end

	newparam(:security_group_ids) do
		desc "A comma separated list of security groups by security group id that you want the instance to join."
		validate do |value|
			groupids=value.split(/\s*,\s*/)
			groupids.each {|id|
				unless id =~ /^sg-/
					raise ArgumentError, "ec2instance: #{id} is not valid, security group ids start 'sg-'"
				end
			}
		end
	end

	newparam(:user_data) do
		desc "The user data which you want to pass the instance when it boots in string format."
	end

	newparam(:kernel_id) do
		desc "The ID of the kernel with which to launch the instance."
		validate do |value|
			unless value =~ /^aki-/
				raise ArgumentError , "ec2instance: #{value} is not valid kernel_id which start 'aki-'"
			end
		end
	end

	newparam(:ramdisk_id) do
		desc "The ID of the RAM disk. Some kernels require additional drivers at launch. Check the kernel requirements for information on whether you need to specify a RAM disk. To find kernel requirements, refer to the Resource Center and search for the kernel ID."
		validate do |value|
			unless value =~ /^ari-/
				raise ArgumentError , "ec2instance: #{value} is not valid ramdisk_id which start 'ari-'"
			end
		end
	end

	newparam(:monitoring_enabled) do
		valid_values=['true', 'false']
		desc "Enables monitoring for the instance."
		defaultto 'false'
		validate do |value|
			unless valid_values.includes?(value)
				raise ArgumentError, "ec2instance: monitoring_enabled should be 'true' or 'false'"
			end
		end
	end

	newparam(:subnet_id) do
		desc "[EC2-VPC] The ID of the subnet to launch the instance into."
	end

	newparam(:private_ip_address) do
		desc "[EC2-VPC] You can optionally use this parameter to assign the instance a specific available IP address from the IP address range of the subnet as the primary IP address."

	end

	newparam(:disable_api_termination) do
		valid_values=['true', 'false']
		desc "Whether you can terminate the instance using the EC2 API. A value of true means you can't terminate the instance using the API (i.e., the instance is 'locked'); a value of false means you can."
		defaultto 'false'
		validate do |value|
			unless valid_values.includes?(value)
				raise ArgumentError, "ec2instance: disable_api_termination should be 'true' or 'false'"
			end
		end
	end

	newparam(:instance_initiated_shutdown_behavior) do
		valid_values=['stop', 'terminate']
		desc "Whether the instance stops or terminates on instance-initiated shutdown."
		defaultto 'stop'
		validate do |value|
			unless valid_values.includes?(value)
				raise ArgumentError, "ec2instance: instance_initiated_shutdown_behavior should be 'stop' or 'terminate'"
			end
		end
	end

	newparam(:ebs_optimized) do
		valid_values=['true', 'false']
		desc "Whether the instance is optimized for EBS I/O. This optimization provides dedicated throughput to Amazon EBS and an optimized configuration stack to provide optimal EBS I/O performance. This optimization isn't available with all instance types. Additional usage charges apply when using an EBS Optimized instance."
		defaultto 'false'
		validate do |value|
			unless valid_values.includes?(value)
				raise ArgumentError, "ec2instance: ebs_optimized should be 'true' or 'false'"
			end
		end
	end

	# Expert Options

	#   * 'BlockDeviceMapping'<~Array>: array of hashes
	#     * 'DeviceName'<~String> - where the volume will be exposed to instance
	#     * 'VirtualName'<~String> - volume virtual device name
	#     * 'Ebs.SnapshotId'<~String> - id of snapshot to boot volume from
	#     * 'Ebs.VolumeSize'<~String> - size of volume in GiBs required unless snapshot is specified
	#     * 'Ebs.DeleteOnTermination'<~String> - specifies whether or not to delete the volume on instance termination

	# Wouldn't it be great if you could pass structured data to your puppet params or properties?
	# Trying to pass the structured data for these blockdevicemappings as a YAML encoded string: e.g.

	# ---
	# - DeviceName: /dev/xvdb
	#   VirtualName: ephemeral3
	# - DeviceName: /dev/xvdc
	#   Ebs.SnapshotId: snap-xyz123  
	#   Ebs.DeleteOnTermination: false
	# - DeviceName: /dev/xvdd
	#   Ebs.VolumeSize: 100

	# This is a complete experiment and unlikely to work.  I'm going to get the basic functionality working first.

	newparam(:block_device_mapping) do
		desc "Expert Feature: block_device_mapping is expected to be a yaml encoded array of hashes which contain valid block device mapping information to the instance when it launches.  See http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/block-device-mapping-concepts.html for more information." 
		munge do |value|
			begin
				YAML.load(value)
			rescue
				raise ArgumentError, "ec2instance: Sorry couldn't parse/load YAML in block_device_mapping, please check syntax."
			end
		end
		unmunge do |value|
			YAML.dump(value)
		end
	end

end
