require 'rubygems'
require 'facter'
require 'fog'
require 'yaml'

Puppet::Type.newtype(:ec2instance) do
	@doc = "Manage EC2 Instances"

	# Allow to be ensurable
	ensurable

	newparam(:Name) do
		desc "The friendly Name (tag) of the EC2 Instance"
		isnamevar
		isrequired
	end

	newparam(:AvailabilityZone) do
		desc "The availability zone that the instance should run in"
		isrequired
		defaultto do
			Facter.value('ec2_placement_availability_zone') 
		end
	end

	newparam(:InstanceType) do
		valid_types = [ 't1.micro','m1.small','m1.medium','m1.large','m1.xlarge','m3.xlarge','m3.2xlarge','c1.medium','c1.xlarge','m2.xlargei','m2.2xlarge','m2.4xlarge','cr1.8xlarge','hi1.4xlarge','hs1.8xlarge','cc1.4xlarge','cc2.8xlarge','cg1.4xlarge' ]
		desc "The instance type: Valid values are: #{valid_types.join(', ')}"
		isrequired
		defaultto 'm1.small'
		validate do |value|
			unless valid_types.include?(value)
				raise ArgumentError , "ec2instance: #{value} is not valid InstanceType"
			end
		end
	end

	newparam(:ImageId) do
		desc "The ImageID for the AMI to boot from"
		isrequired
		validate do |value|
			unless value =~ /^ami-/
				raise ArgumentError , "ec2instance: #{value} is not valid ImageId which start 'ami-'"
			end
		end
	end

	newparam(:MinCount) do
		desc "The minimum number of instances to launch."
		isrequired
		defaultto 1
		validate do |value|
			unless value =~ /^[0-9]+$/
				raise ArgumentError , "ec2instance: #{value} is not a valid, MinCount needs to be an integer."
			end
		end
	end

	newparam(:MaxCount) do
		desc "The maximum number of instances to launch."
		isrequired
		defaultto 1
		validate do |value|
			unless value =~ /^[0-9]+$/
				raise ArgumentError , "ec2instance: #{value} is not a valid, MaxCount needs to be an integer."
			end
		end
	end

	newparam(:KeyName) do
		desc "The name of the key pair to use."
	end

	newparam(:SecurityGroupNames) do
		desc "A comma separated list of security groups by Name that you want the instance to join."
	end

	newparam(:SecurityGroupIds) do
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

	newparam(:UserData) do
		desc "The user data which you want to pass the instance when it boots in string format."
	end

	newparam(:UserData64) do
		desc "The user data which you want to pass the instance when it boots in Base64 format."
	end

	newparam(:KernelId) do
		desc "The ID of the kernel with which to launch the instance."
		validate do |value|
			unless value =~ /^aki-/
				raise ArgumentError , "ec2instance: #{value} is not valid KernelId which start 'aki-'"
			end
		end
	end

	newparam(:RamdiskId) do
		desc "The ID of the RAM disk. Some kernels require additional drivers at launch. Check the kernel requirements for information on whether you need to specify a RAM disk. To find kernel requirements, refer to the Resource Center and search for the kernel ID."
		validate do |value|
			unless value =~ /^ari-/
				raise ArgumentError , "ec2instance: #{value} is not valid RamdiskId which start 'ari-'"
			end
		end
	end

	newparam(:MonitoringEnabled) do
		valid_values=['true', 'false']
		desc "Enables monitoring for the instance."
		defaultsto 'false'
		validate do |value|
			unless valid_values.includes?(value)
				raise ArgumentError, "ec2instance: MonitoringEnabled should be 'true' or 'false'"
			end
		end
	end

	newparam(:SubnetId) do
		desc "[EC2-VPC] The ID of the subnet to launch the instance into."
	end

	newparam(:PrivateIpAddress) do
		desc "[EC2-VPC] You can optionally use this parameter to assign the instance a specific available IP address from the IP address range of the subnet as the primary IP address.

			Only one private IP address can be designated as primary. Therefore, you cannot specify this parameter if you are also specifying PrivateIpAddresses.n.Primary with a value of true with the PrivateIpAddresses.n.PrivateIpAddress option."
	end

	newparam(:DisableApiTermination) do
		valid_values=['true', 'false']
		desc "Whether you can terminate the instance using the EC2 API. A value of true means you can't terminate the instance using the API (i.e., the instance is 'locked'); a value of false means you can. If you set this to true, and you later want to terminate the instance, you must first change the disableApiTermination attribute's value to false using ModifyInstanceAttribute."
		defaultto 'false'
		validate do |value|
			unless valid_values.includes?(value)
				raise ArgumentError, "ec2instance: DisableApiTermination should be 'true' or 'false'"
			end
		end
	end

	newparam(:InstanceInitiatedShutdownBehavior) do
		valid_values=['stop', 'terminate']
		desc "Whether the instance stops or terminates on instance-initiated shutdown."
		defaultto 'stop'
		validate do |value|
			unless valid_values.includes?(value)
				raise ArgumentError, "ec2instance: InstanceInitiatedShutdownBehavior should be 'stop' or 'terminate'"
			end
		end
	end

	newparam(:EbsOptimized) do
		valid_values=['true', 'false']
		desc "Whether the instance is optimized for EBS I/O. This optimization provides dedicated throughput to Amazon EBS and an optimized configuration stack to provide optimal EBS I/O performance. This optimization isn't available with all instance types. Additional usage charges apply when using an EBS Optimized instance."
		defaultto 'false'
		validate do |value|
			unless valid_values.includes?(value)
				raise ArgumentError, "ec2instance: EbsOptimized should be 'true' or 'false'"
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

	newparam(:BlockDeviceMapping) do
		desc "Expert Feature: BlockDeviceMapping is expected to be a yaml encoded array of hashes which contain valid block device mapping information to the instance when it launches.  See http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/block-device-mapping-concepts.html for more information." 
		munge do |value|
			begin
				YAML.load(value)
			rescue
				raise ArgumentError, "ec2instance: Sorry couldn't parse/load YAML in BlockDeviceMapping, please check syntax."
			end
		end
		unmunge do |value|
			YAML.dump(value)
		end
	end
			


end
