require 'rubygems'
require 'fog'
require 'facter'
require 'pp'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','puppet_x','practicalclouds','connection.rb'))

Puppet::Type.type(:ec2instance).provide(:fog) do
	desc "The AWS Provider which implements the ec2instance type."

	# Only allow the provider if fog is installed.
	commands :fog => 'fog'

	mk_resource_methods

	def self.instances
		regions = PuppetX::Practicalclouds::Awsaccess.regions('default')
		regions = ['us-east-1','us-west-1','us-west-2','eu-west-1','ap-southeast-1','ap-southeast-2','ap-northeast-1','sa-east-1'] if (regions==[])

		# get a list of instances in all of the regions we are configured for.
		allinstances=[]
		regions.each {|reg|	
			compute = PuppetX::Practicalclouds::Awsaccess.connect(reg,'default')	
			debug "Querying region #{reg}"
			resp = compute.describe_instances
			if (resp.status == 200)
				# check through the instances looking for one with a matching Name tag
				resp.body['reservationSet'].each do |x|
					secprops={}
					secprops[:security_group_names] = x['groupSet']
					secprops[:security_group_ids] = x['groupIds']
					x['instancesSet'].each do |y|
						myname = y['tagSet']['Name'] ? y['tagSet']['Name'] : y['instanceId']
						debug "Found ec2instance instance : #{myname}"
						instprops = { :name => myname,
							:ensure => :present,
							:region => reg,
							:availability_zone => y['placement']['availabilityZone'] 
						}
						instprops[:instance_id] = y['instanceId'] if y['instanceId']
						instprops[:instance_type] = y['instanceType'] if y['instanceType']
						instprops[:key_name] = y['keyName'] if y['keyName']
						instprops[:kernel_id] = y['kernelId'] if y['kernelId']
						instprops[:image_id] = y['imageId'] if y['imageId']
						instprops[:ramdisk_id] = y['ramdiskId'] if y['ramdiskId']
						instprops[:subnet_id] = y['subnetId'] if y['subnetId']
						instprops[:private_ip_address] = y['privateIpAddress'] if y['privateIpAddress']
						instprops[:ebs_optimized] = y['ebsOptimized'] if y['ebsOptimized']
						instprops[:ip_address] = y['ipAddress'] if y['ipAddress']
						instprops[:architecture] = y['architecture'] if y['architecture']
						instprops[:dns_name] = y['dnsName'] if y['dnsName']
						instprops[:private_dns_name] = y['privateDnsName'] if y['privateDnsName']
						instprops[:root_device_type] = y['rootDeviceType'] if y['rootDeviceType']
						instprops[:launch_time] = y['launchTime'] if y['launchTime']
						instprops[:virtualization_type] = y['virtualizationType'] if y['virtualizationType']
						instprops[:owner_id] = y['ownerId'] if y['ownerId']
						instprops[:tags] = y['tagSet'] if y['tagSet']
						instprops[:instance_state] = y['instanceState']['name'] if y['instanceState']['name']
						instprops[:network_interfaces] = y['networkInterfaces'] if y['networkInterfaces'] != []
						instprops[:block_device_mapping] = y['blockDeviceMapping'] if y['blockDeviceMapping'] != []
					
						instprops.merge!(secprops)
						allinstances << instprops
					end
				end	
			else
				raise "Sorry, I could not retrieve a list of instances from #{region}!"
			end
		}

		# return the list of instances
		#puts "I found these instances..."
		#pp allinstances

		# return the array of resources
		allinstances.map {|x| new(x)}
	end

	def self.prefetch(resources)
		configs = instances
		resources.keys.each do |name|
			if provider = configs.find{ |conf| conf.name == name}
				resources[name].provider = provider
			end
		end
	end

   def exists?
      @property_hash[:ensure] == :present
   end

	def myregion
      if (@resource[:availability_zone])
         return @resource[:availability_zone].gsub(/.$/,'')
      elsif (@resource[:region])
         return @resource[:region]
      end
		raise "Sorry, I could not work out my region"
	end

	def myaccess
      name = (@resource[:awsaccess]) ? @resource[:awsaccess] : 'default'
		name
	end

	def create
		#complex_params = [ :security_group_names, :security_group_ids, :block_device_mapping ]
		options_hash={}

		# check required parameters...
		[ :name, :image_id ].each {|a|
			if (!@resource[a])
				notice "Missing required attribute #{a}!"
				raise "Sorry, you must include \"#{a}\" when defining an ec2instance instance"
			end
		}

		# lookup the imageid
		compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)
		response = compute.describe_images({ 'ImageId' => @resource[:image_id]}) 
		raise "Sorry, I couldn't lookup image #{@resource[:image_id]}" if (response.status != 200)
		aminame = response.body['imagesSet'][0]['name']
		# Root device type, ebs or instance-store
		amirootdevicetype = response.body['imagesSet'][0]['rootDeviceType']

		[ :ip_address, :architecture, :dns_name, :private_dns_name, :root_device_type, :launch_time, :virtualization_type, :owner_id, :instance_state, :network_interfaces ].each {|a|	
			info("Ignoring READONLY attribute #{a}") if (@resource[a])
		}

		# set up the options hash
		options_hash['Placement.AvailabilityZone'] = @resource[:availability_zone].to_s if @resource[:availability_zone]
		options_hash['Placement.GroupName'] = @resource[:placement_group_name].to_s if @resource[:placement_group_name]
		options_hash['DisableApiTermination'] = @resource[:disable_api_termination].to_s if @resource[:disable_api_termination]
		options_hash['DisableApiTermination'] = @resource[:disable_api_termination].to_s if @resource[:disable_api_termination]
		options_hash['SecurityGroup'] = @resource[:security_group_names] if @resource[:security_group_names]
		options_hash['SecurityGroupId'] = @resource[:security_group_ids] if @resource[:security_group_ids]
		options_hash['InstanceType'] = @resource[:instance_type].to_s if @resource[:instance_type]
		options_hash['KernelId'] = @resource[:kernel_id].to_s if @resource[:kernel_id]
		options_hash['KeyName'] = @resource[:key_name].to_s if @resource[:key_name]
		options_hash['Monitoring.Enabled'] = @resource[:monitoring_enabled] if @resource[:monitoring_enabled]
		options_hash['PrivateIpAddress'] = @resource[:private_ip_address].to_s if @resource[:private_ip_address]
		options_hash['RamdiskId'] = @resource[:ramdisk_id].to_s if @resource[:ramdisk_id]
		options_hash['SubnetId'] = @resource[:subnet_id].to_s if @resource[:subnet_id]
		options_hash['UserData'] = @resource[:user_data].to_s if @resource[:user_data]
		options_hash['EbsOptimized'] = @resource[:ebs_optimized] if @resource[:ebs_optimized]
		# ebs only options
		if (amirootdevicetype == 'ebs')
			options_hash['InstanceInitiatedShutdownBehavior'] = @resource[:instance_initiated_shutdown_behavior].to_s if @resource[:instance_initiated_shutdown_behavior]
		end

		# start the instance
		notice "Creating new ec2instance '#{@resource[:name]}' from image #{@resource[:image_id]}"
		info "#{@resource[:image_id]}: #{aminame}"
		debug "compute.run_instances(#{@resource[:image_id]},1,1,options_hash)"
		debug "options_hash (YAML):-\n#{options_hash.to_yaml}"

		response = compute.run_instances(@resource[:image_id],1,1,options_hash)	
		if (response.status == 200)
			sleep 5

			# Add the required tags...
			instid = response.body['instancesSet'][0]['instanceId']
			if (@resource[:tags])
				@resource[:tags]['Name']=@resource[:name].to_s
			else
				@resource[:tags] = { 'Name' => @resource[:name].to_s }
			end
			debug "Naming instance #{instid} : #{@resource['tags']['Name']}"
			assign_tags(instid,@resource['tags'])

			# optionally wait for the instance to be "running"
			if (@resource[:wait] == :true)
				wait_state(instid,'running',@resource[:max_wait])
			end
		else
			raise "I couldn't create the ec2 instance, sorry! API Error!"
		end
	end

	def destroy
		instance = instanceinfo(@resource[:name])
		if (instance)
			notice "Terminating ec2 instance #{@resource[:name]} : #{instance['instanceId']}"
		else
			raise "Sorry I could not lookup the instance with name #{@resource[:name]}" if (!instance)
		end

		debug "compute.terminate_instances(#{instance['instanceId']})"
		compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)
		response = compute.terminate_instances(instance['instanceId'])
		if (response.status != 200)
			raise "I couldn't terminate ec2 instance #{instance['instanceId']}"
		else
			if (@resource[:wait] == :true)
				wait_state(@resource[:name],'terminated',@resource[:max_wait])
			end
			notice "Removing Name tag #{@resource[:name]} from #{instance['instanceId']}"
			debug "compute.delete_tags(#{instance['instanceId']},{ 'Name' => #{@resource[:name]}})"
			response = @compute.delete_tags(instance['instanceId'],{ 'Name' => @resource[:name]}) 
			if (response.status != 200)
				raise "I couldn't remove the Name tag from ec2 instance #{instance['instanceId']}"
			end
		end
	end

	#---------------------------------------------------------------------------------------------------
	# Properties which can't be changed...

	def availability_zone=(value)
		fail "Sorry you can't change the availability_zone of a running ec2instance"
	end

	def region=(value)
		fail "Sorry you can't change the region of a running ec2instance"
	end

	def instance_type=(value)
		fail "Sorry you can't change the instance_type of a running ec2instance"
	end

	def image_id=(value)
		fail "Sorry you can't change the image_id of a running ec2instance"
	end

	def image_id=(value)
		fail "Sorry you can't change the image_id of a running ec2instance"
	end

	def subnet_id=(value)
		fail "Sorry you can't change the subnet_id of a running ec2instance"
	end

	#---------------------------------------------------------------------------------------------------
	# Properties which CAN be changed...

	        # ==== Parameters
        # * instance_id<~String> - Id of instance to modify
        # * attributes<~Hash>:
        #   'InstanceType.Value'<~String> - New instance type
        #   'Kernel.Value'<~String> - New kernel value
        #   'Ramdisk.Value'<~String> - New ramdisk value
        #   'UserData.Value'<~String> - New userdata value
        #   'DisableApiTermination.Value'<~Boolean> - Change api termination value
        #   'InstanceInitiatedShutdownBehavior.Value'<~String> - New instance initiated shutdown behaviour, in ['stop', 'terminate']
        #   'SourceDestCheck.Value'<~Boolean> - New sourcedestcheck value
        #   'GroupId'<~Array> - One or more groups to add instance to (VPC only)

	def security_group_names=(value)
		debug "TODO: Modify the assigned security groups.."
   end

	def security_group_ids=(value)
		debug "TODO: Modify the assigned security groups.."
   end

	def kernel_value=(value)
		debug "TODO: Modify the kernel id"
   end

	def ramdisk_value=(value)
		debug "TODO: Modify the ramdisk id"
   end

	def monitoring_enabled=(value)
		debug "TODO: Enable/disable monitoring..."
   end

	def tags=(value)
		debug "#{@resource[:name]} needs its tags updating..."
		debug "Requested tags (YAML):-\n#{@resource[:tags].to_yaml}"
		debug "Actual tags (YAML):-\n#{@property_hash[:tags].to_yaml}"
		assign_tags(@property_hash[:instance_id],value)
	end

	# for looking up information about an ec2 instance given the Name tag
	def instanceinfo(name)
		debug "compute.describe_instances"
		compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)
		resp = compute.describe_instances	
		if (resp.status == 200)
			# check through the instances looking for one with a matching Name tag
			resp.body['reservationSet'].each { |x|
				x['instancesSet'].each { |y| 
					if ( y['tagSet']['Name'] == name)
						return y
					end
				}
			}
		else
			raise "I couldn't list the instances"
		end
		false	
	end	

	# generic method to wait for an array of instances to reach a desired state...
	def wait_state(name,desired_state,max)
		elapsed_wait=0
		check = instanceinfo(name)
		if ( check )
			notice "Waiting for instance #{name} to be #{desired_state}"
			while ( check['instanceState']['name'] != desired_state && elapsed_wait < max ) do
				debug "instance #{name} is #{check['instanceState']['name']}"
				sleep 5
				elapsed_wait += 5
				check = instanceinfo(name)
			end
			if (elapsed_wait >= max)
				raise "Timed out waiting for name to be #{desired_state}"
			else
				notice "Instance #{name} is now #{desired_state}"
			end
		else
			raise "Sorry, I couldn't find instance #{name}"
		end
	end

	# add/delete or modify tags on a resource so that they match the taghash
	def assign_tags(resourceid,taghash)
		mytags={}
		debug "compute.describe_tags"
		compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)
		resp=compute.describe_tags
		if (resp.status == 200)
			resp.body['tagSet'].each do |tags|
				tags.each do |tag|
					if (tag['resourceid'] == resourceid)
						mytags[tag['key']] = tag['value']
					end
				end
			end
		else
			raise "I couldn't read the tags!"
		end
		
		# delete any tags which are not in the tag hash or havedifferent values
		if (mytags != {})
			deletetags={}
			mytags.each do |tag|
				if (tag['value'] != taghash[tag['key']]) 
					debug "Deleting tag #{tag['key']} = #{tag['value']} from #{resourceid}"
					deletetags[tag['key']] = tag['value']
					mytags.delete(tag['key'])
				end
			end
			debug "compute.delete_tags(#{resourceid},deletetags)"
			debug "deletetags (YAML):-\n#{deletetags.to_yaml}"
			resp=compute.delete_tags(resourceid,deletetags)
			if (resp.status != 200)
				raise "I couldn't delete the tags!"
			end
		end
	
		# now add the new tags
		if (taghash != {})
			addtags={}
			taghash.each_pair do |t,v|
				if (!mytags[t])
					debug "Adding tag #{t} = #{v} to #{resourceid}"
					addtags[t]=v if (!mytags[t])
				end
			end
			debug "compute.create_tags(#{resourceid},addtags)"
			debug "addtags (YAML):-\n#{addtags.to_yaml}"
         response = compute.create_tags(resourceid,addtags)
         if (response.status != 200)
            raise "I couldn't add tags to #{resourceid}"
         end
		end
	end

end
