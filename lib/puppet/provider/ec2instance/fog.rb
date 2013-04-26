require 'rubygems'
require 'fog'
require 'facter'
require 'pp'

Puppet::Type.type(:ec2instance).provide(:fog) do
	desc "The AWS Provider which implements the ec2instance type."

	# Only allow the provider if fog is installed.
	commands :fog => 'fog'

	@allawsregions=['us-east-1','us-west-1','us-west-2','eu-west-1','ap-southeast-1','ap-southeast-2','ap-northeast-1','sa-east-1']
	@required_atts=[ :name, :image_id ]
	@readonly_atts=[ :ip_address, :architecture, :dns_name, :private_dns_name, :root_device_type, :launch_time, :virtualization_type, :owner_id, :instance_state, :network_interfaces ]

	# function to set the access keys to the desired set...
   def self.get_access(name, any=false)
      yamlfile = "#{Puppet[:confdir]}/aws.yaml"

      # load in an awsaccess object for connecting to AWS.
      return {} if (!File.exists?(yamlfile))
      cfghash = YAML::load(File.open(yamlfile))
      if (cfghash.length >=1) then
         # choose the default access for retrieving a list of instances
         if (cfghash[name]) then
            debug "Setting awsaccess credentials to : #{name}"
            return cfghash['default']
         elsif (any)
            # pick the first one
            debug "Setting awsaccess credentials to the first credentials : #{cfghash.keys[0]}"
            return cfghash[0]
         end
      end
      return {}
   end

	def self.instances
		cred=get_access('default',true)
		if (!cred[:aws_access_key_id] || !cred[:aws_secret_access_key])
			return []
		end
		regions=cred[:regions] ? cred[:regions] : @allawsregions

		# get a list of instances in all of the regions we are configured for.
		allinstances=[]
		regions.each {|reg|	
			compute = Fog::Compute.new(:provider => 'aws', :aws_access_key_id => cred[:aws_access_key_id], :aws_secret_access_key => cred[:aws_secret_access_key], :region => "#{reg}")	
			debug "Querying region #{reg}"
			resp = compute.describe_instances
			if (resp.status == 200)
				readprops={}
				# check through the instances looking for one with a matching Name tag
				resp.body['reservationSet'].each do |x|
					readprops[:security_group_names] = x['groupSet']
					readprops[:security_group_ids] = x['groupIds']
					x['instancesSet'].each do |y|
						myname = y['tagSet']['Name'] ? y['tagSet']['Name'] : y['instanceId']
						debug "Found ec2instance instance : #{myname}"
						readprops.merge!({ :name => myname,
							:ensure => :present,
							:region => reg,
							:availability_zone => y['placement']['availabilityZone'] 
						})
						readprops[:instance_type] = y['instanceType'] if y['instanceType']
						readprops[:key_name] = y['keyName'] if y['keyName']
						readprops[:kernel_id] = y['kernelId'] if y['kernelId']
						readprops[:image_id] = y['imageId'] if y['imageId']
						readprops[:ramdisk_id] = y['ramdiskId'] if y['ramdiskId']
						readprops[:subnet_id] = y['subnetId'] if y['subnetId']
						readprops[:private_ip_address] = y['privateIpAddress'] if y['privateIpAddress']
						readprops[:ebs_optimized] = y['ebsOptimized'] if y['ebsOptimized']
						readprops[:ip_address] = y['ipAddress'] if y['ipAddress']
						readprops[:architecture] = y['architecture'] if y['architecture']
						readprops[:dns_name] = y['dnsName'] if y['dnsName']
						readprops[:private_dns_name] = y['privateDnsName'] if y['privateDnsName']
						readprops[:root_device_type] = y['rootDeviceType'] if y['rootDeviceType']
						readprops[:launch_time] = y['launchTime'] if y['launchTime']
						readprops[:virtualization_type] = y['virtualizationType'] if y['virtualizationType']
						readprops[:owner_id] = y['ownerId'] if y['ownerId']
						readprops[:tags] = y['tagSet'] if y['tagSet']
						readprops[:instance_state] = y['instanceState']['name'] if y['instanceState']['name']
						readprops[:network_interfaces] = y['networkInterfaces'] if y['networkInterfaces'] != []
						readprops[:block_device_mapping] = y['blockDeviceMapping'] if y['blockDeviceMapping'] != []
						allinstances << readprops
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

	mk_resource_methods

   def exists?
      # set up awsaccess credentials
      @cred={}
      if @resource['awsaccess'] then
         @cred=Puppet::Type::Ec2instance::ProviderFog::get_access(@resource['awsaccess'],false)
      else
         @cred=Puppet::Type::Ec2instance::ProviderFog::get_access('default',true)
      end
      if (!@cred[:aws_access_key_id] || !@cred[:aws_secret_access_key])
         fail "Can't find any awsaccess resources to use to connect to amazon.  Please configure at least one awsaccess resource!"
      end
      @compute = Fog::Compute.new(:provider => 'aws', :aws_access_key_id => @cred[:aws_access_key_id], :aws_secret_access_key => @cred[:aws_secret_access_key], :region => "#{region}")
      Fog::mock!

      @property_hash[:ensure] == :present
   end

	def create
		notice "Creating new ec2 instance with name #{@resource[:name]}"
		#complex_params = [ :security_group_names, :security_group_ids, :block_device_mapping ]
		options_hash={}

		# check required parameters...
		@required_atts.each {|a|
			if (!@resource[a])
				notice "Missing required attribute #{a}!"
				raise "Sorry, you must include \"#{a}\" when defining an ec2instance instance"
			end
		}

		@readonly_atts.each {|a|	
			info("Ignoring READONLY attribute #{a}")
		}

		# set up the options hash
		options_hash['Placement.AvailabilityZone'] = @resource[:availability_zone] if @resource[:availability_zone]
		options_hash['Placement.GroupName'] = @resource[:group_name] if @resource[:group_name]
		options_hash['DisableApiTermination'] = @resource[:disable_api_termination] if @resource[:disable_api_termination]
		options_hash['DisableApiTermination'] = @resource[:disable_api_termination] if @resource[:disable_api_termination]
		options_hash['SecurityGroup'] = @resource[:security_group_names] if @resource[:security_group_names]
		options_hash['SecurityGroupId'] = @resource[:security_group_ids] if @resource[:security_group_ids]
		options_hash['InstanceInitiatedShutdownBehaviour'] = @resource[:instance_initiated_shutdown_behavior] if @resource[:instance_initiated_shutdown_behavior]
		options_hash['InstanceType'] = @resource[:instance_type] if @resource[:instance_type]
		options_hash['KernelId'] = @resource[:kernel_id] if @resource[:kernel_id]
		options_hash['KeyName'] = @resource[:key_name] if @resource[:key_name]
		options_hash['Monitoring.Enabled'] = @resource[:monitoring_enabled] if @resource[:monitoring_enabled]
		options_hash['PrivateIpAddress'] = @resource[:private_ip_address] if @resource[:private_ip_address]
		options_hash['RamdiskId'] = @resource[:ramdisk_id] if @resource[:ramdisk_id]
		options_hash['SubnetId'] = @resource[:subnet_id] if @resource[:subnet_id]
		options_hash['UserData'] = @resource[:user_data] if @resource[:user_data]
		options_hash['EbsOptimized'] = @resource[:ebs_optimized] if @resource[:ebs_optimized]

		# start the instance
		notice "Creating new ec2instance '#{@resource[:name]} from image #{@resource[:image_id]}"
		response = @compute.run_instances(@resource[:image_id],1,1,options_hash)	
		if (response.status == 200)
			sleep 5

			# Add the required tags...
			instid = response.body['instancesSet'][0]['instanceId']
			@resource['tags']['Name']="#{@resource[:name]}"
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
		response = @compute.terminate_instances(instance['instanceId'])
		if (response.status != 200)
			raise "I couldn't terminate ec2 instance #{instance['instanceId']}"
		else
			if (@resource[:wait] == :true)
				wait_state(@resource[:name],'terminated',@resource[:max_wait])
			end
			notice "Removing Name tag #{@resource[:name]} from #{instance['instanceId']}"
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
	# Properties where changes can be ignored...



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

	# for looking up information about an ec2 instance given the Name tag
	def instanceinfo(name)
		resp = @compute.describe_instances	
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
		resp=@compute.describe_tags
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
			resp=@compute.delete_tags(resourceid,deletetags)
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
         response = @compute.create_tags(resourceid,addtags)
         if (response.status != 200)
            raise "I couldn't add tags to #{resourceid}"
         end
		end
	end

end
