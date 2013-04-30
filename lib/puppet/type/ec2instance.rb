require 'rubygems'
require 'facter'
require 'fog'
require 'yaml'
require 'pp'

Puppet::Type.newtype(:ec2instance) do
	@doc = "EC2 Instances"

	# Allow to be ensurable
	ensurable

	# --------------------------------------------------------------------------------------------------------------
	# Parameters  

	newparam(:name) do
		desc "The friendly Name (tag) of the EC2 Instance"
		isnamevar
		isrequired
	end

	newparam(:awsaccess) do
		desc "Optional name of an awsaccess resource to use for managing this resource"
		validate do |value|
			# we must have a matching awsaccess resource in the catalog
			found=false
			@resource.catalog.resources.each do |d|
            if (d.class.to_s == "Puppet::Type::Awsaccess")
					found=true if (d.name == value)
            end
        	end 
			raise ArgumentError, "Sorry, you need to have a matching awsaccess resource in your manifest when specifying the awsaccess attribute!" if (found==false)
		end
	end

	#newparam(:min_count) do
	#	desc "The minimum number of instances to launch."
	#	defaultto '1'
	#	newvalues(/^\d+$/)
	#end

	#newparam(:max_count) do
	#	desc "The maximum number of instances to launch."
	#	defaultto '1'
	#	newvalues(/^\d+$/)
	#end

	newparam(:wait) do
		desc "Whether to wait for the instance to finish starting up before returning from the provider."
		newvalues(:true, :false)
		defaultto :false
	end

	newparam(:placement_group_name) do
		desc "The placement group for the instance"
	end

	newparam(:max_wait) do
		desc "How long to keep on waiting for an instance to start before throwing an error, in seconds"
		newvalues(/^\d+/)
		defaultto 600
	end

	newparam(:user_data) do
		desc "The user data which you want to pass the instance when it boots in string format."
	end

	newparam(:disable_api_termination) do
		desc "Whether you can terminate the instance using the EC2 API. A value of true means you can't terminate the instance using the API (i.e., the instance is 'locked'); a value of false means you can."
		newvalues(:true, :false)
		defaultto :false
	end

	newparam(:instance_initiated_shutdown_behavior) do
		desc "Whether the instance stops or terminates on instance-initiated shutdown."
		newvalues(:stop, :terminate)
		defaultto :stop
	end

	# --------------------------------------------------------------------------------------------------------------
	# Properties  

	# AvailabilityZone and Region - we need to determine which aws region we need to communicate with.
	# The user can specify either the availability zone or a region. If they specify an availability zone
	# then we will calculate the region from that.
	newproperty(:availability_zone) do
		desc "The availability zone that the instance should run in"
		newvalues(/^eu-west-\d[a-z]$/, /^us-east-\d[a-z]$/, /^us-west-\d[a-z]$/, /^ap-southeast-\d[a-z]$/, /^ap-northeast-\d[a-z]$/, /^sa-east-\d[a-z]$/) 
	end

	# If the user does not select a specific availability zone then they can choose a region and the instance
	# will be started in any of the availability zones in that region.  If no region is specified then we
	# will automatically choose the same region as the server owning the ec2instance resource (the one 
	# performing the puppet run)
	newproperty(:region) do
		desc "The region that this instance belongs."
		newvalues(/^eu-west-\d$/, /^us-east-\d$/, /^us-west-\d$/, /^ap-southeast-\d$/, /^ap-northeast-\d$/, /^sa-east-\d$/) 
		#defaultto do
		#	self[:availability_zone] ? self[:availability_zone].gsub(/.$/,'') : Facter.value('ec2_placement_availability_zone').gsub(/.$/,'')
		#end
	end

	newproperty(:instance_type) do
		desc "The instance type"
		defaultto :'m1.small'
		newvalues(:"t1.micro", :"m1.small", :"m1.medium", :"m1.large", :"m1.xlarge", :"m3.xlarge", :"m3.2xlarge", :"c1.medium", :"c1.xlarge", :"m2.xlarge", :"m2.2xlarge", :"m2.4xlarge", :"cr1.8xlarge", :"hi1.4xlarge", :"hs1.8xlarge", :"cc1.4xlarge", :"cc2.8xlarge", :"cg1.4xlarge")
	end

	newproperty(:image_id) do
		desc "The image_id for the AMI to boot from"
		isrequired
		newvalues(/^ami-/)
	end

	newproperty(:key_name) do
		desc "The name of the key pair to use."
	end

	newproperty(:security_group_names, :array_matching => :all) do
		desc "A list of security groups by Name that you want the instance to join."
	end

	newproperty(:security_group_ids, :array_matching => :all) do
		desc "A list of security groups by security group id that you want the instance to join."
		newvalues(/^sg-/)
	end

	newproperty(:kernel_id) do
		desc "The ID of the kernel with which to launch the instance."
		newvalues(/^aki-/)
	end

	newproperty(:ramdisk_id) do
		desc "The ID of the RAM disk. Some kernels require additional drivers at launch. Check the kernel requirements for information on whether you need to specify a RAM disk. To find kernel requirements, refer to the Resource Center and search for the kernel ID."
		newvalues(/^ari-/)
	end

	newproperty(:monitoring_enabled) do
		desc "Enables monitoring for the instance."
		newvalues(:true, :false)
		defaultto :false
	end

	newproperty(:subnet_id) do
		desc "[EC2-VPC] The ID of the subnet to launch the instance into."
	end

	newproperty(:private_ip_address) do
		desc "[EC2-VPC] You can optionally use this parameter to assign the instance a specific available IP address from the IP address range of the subnet as the primary IP address."
	end

	newproperty(:instance_id) do
		desc "READONLY: The amazon AWS instanceId of the instance"
		munge do |v|
			nil
		end
		unmunge do |v|
			nil
		end
	end

	newproperty(:ip_address) do
		desc "READONLY: The public IP address of the instance"
		munge do |v|
			nil
		end
		unmunge do |v|
			nil
		end
	end

	newproperty(:architecture) do
		desc "READONLY: i386 or x86_64"
		munge do |v|
			nil
		end
		unmunge do |v|
			nil
		end
	end

	newproperty(:dns_name) do
		desc "READONLY: The instances public DNS name"
		munge do |v|
			nil
		end
		unmunge do |v|
			nil
		end
	end

	newproperty(:private_dns_name) do
		desc "READONLY: The instances private DNS name"
		munge do |v|
			nil
		end
		unmunge do |v|
			nil
		end
	end

	newproperty(:root_device_type) do
		desc "READONLY: The type of the root device"
		munge do |v|
			nil
		end
		unmunge do |v|
			nil
		end
	end

	newproperty(:launch_time) do
		desc "READONLY: The time an instance was launched"
		munge do |v|
			nil
		end
		unmunge do |v|
			nil
		end
	end

	newproperty(:virtualization_type) do
		desc "READONLY: The type of virtualization"
		munge do |v|
			nil
		end
		unmunge do |v|
			nil
		end
	end

	newproperty(:owner_id) do
		desc "READONLY: The AWS ID of the Owner"
		munge do |v|
			nil
		end
		unmunge do |v|
			nil
		end
	end

	newproperty(:instance_state) do
		desc "READONLY: The state of the ec2instance"
		munge do |v|
			nil
		end
		unmunge do |v|
			nil
		end
	end

	newproperty(:network_interfaces, :array_matching => :all) do
		desc "READONLY: Network inferface information"
		munge do |v|
			nil
		end
		unmunge do |v|
			nil
		end
	end

	newproperty(:tags ) do
		desc "A set of tags which have been set on the object.  There can only be 10 tags per object including the Name tag"
		#validate do |value|
		#	puts "tags value"
		#	pp value
		#end
		munge do |value|
			temphash=value	
			temphash['Name']=@resource[:name]
			temphash
		end
	end

	newproperty(:ebs_optimized) do
		desc "Whether the instance is optimized for EBS I/O. This optimization provides dedicated throughput to Amazon EBS and an optimized configuration stack to provide optimal EBS I/O performance. This optimization isn't available with all instance types. Additional usage charges apply when using an EBS Optimized instance."
		newvalues(:true, :false)
		defaultto :false
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

	newproperty(:block_device_mapping, :array_matching => :all) do
		desc "Expert Feature: block_device_mapping as a hash" 
	end

	#newproperty(:block_device_mapping) do
	#	desc "Expert Feature: block_device_mapping is expected to be a yaml encoded array of hashes which contain valid block device mapping information to the instance when it launches.  See http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/block-device-mapping-concepts.html for more information." 
	#	munge do |value|
	#		begin
	#			YAML.load(value)
	#		rescue
	#			raise ArgumentError, "ec2instance: Sorry couldn't parse/load YAML in block_device_mapping, please check syntax."
	#		end
	#	end
	#	unmunge do |value|
	#		YAML.dump(value)
	#	end
	#end

	# --------------------------------------------------------------------------------------------------------------
	# Validation and autorequires... 

	validate do
		# Validate that the :availability_zone and :region are correct if both specified.
		if (self[:region] && self[:availability_zone]) 
			if (self[:region] != self[:availability_zone].gsub(/.$/,''))
				raise ArgumentError , "ec2instance: Sorry, availability_zone #{self[:availability_zone]} is in region #{self[:availability_zone].gsub(/.$/,'')}.  Please leave the 'region' blank or correct it."
			end
		end
	end

	# Special autorequire for all objects in the 
	# catalog of certain types

	[ 'awsaccess' ].each {|type|
		autorequire(type.to_sym) do
			requires = []
			catalog.resources.each {|d|
				if (d.class.to_s == "Puppet::Type::#{type.capitalize}")
					requires << d.name
				end
			}
			requires
		end
	}	

end

