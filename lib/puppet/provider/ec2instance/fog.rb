require 'rubygems'
require 'fog'
require 'facter'
require 'pp'
require 'base64'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','puppet_x','practicalclouds','connection.rb'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','puppet_x','practicalclouds','storable.rb'))

Puppet::Type.type(:ec2instance).provide(:fog) do
	desc "The AWS Provider which implements the ec2instance type."

	# Only allow the provider if fog is installed.
	commands :fog => 'fog'

	# We can't use 'mk_resource_methods' because we need our own accessors which return the value
	# being requested if the resource does not exist. 
	#mk_resource_methods

	#---------------------------------------------------------------------------------------------------
	# Puppet resource support and prefetch

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
							:region => reg,
							:availability_zone => y['placement']['availabilityZone'] 
						}
						instprops[:ensure] = y['instanceState']['name'] if y['instanceState']['name']
						instprops[:instance_id] = y['instanceId'] if y['instanceId']
						instprops[:instance_type] = y['instanceType'] if y['instanceType']
						instprops[:key_name] = y['keyName'] if y['keyName']
						instprops[:kernel_id] = y['kernelId'] if y['kernelId']
						instprops[:image_id] = y['imageId'] if y['imageId']
						instprops[:ramdisk_id] = y['ramdiskId'] if y['ramdiskId']
						instprops[:subnet_id] = y['subnetId'] if y['subnetId']
						instprops[:private_ip_address] = y['privateIpAddress'] if y['privateIpAddress']
						instprops[:ip_address] = y['ipAddress'] if y['ipAddress']
						instprops[:architecture] = y['architecture'] if y['architecture']
						instprops[:dns_name] = y['dnsName'] if y['dnsName']
						instprops[:private_dns_name] = y['privateDnsName'] if y['privateDnsName']
						instprops[:root_device_type] = y['rootDeviceType'] if y['rootDeviceType']
						instprops[:launch_time] = y['launchTime'] if y['launchTime']
						instprops[:virtualization_type] = y['virtualizationType'] if y['virtualizationType']
						instprops[:vpc_id] = y['vpcId'] if y['vpcId']
						instprops[:subnet_id] = y['subnetId'] if y['subnetId']
						instprops[:owner_id] = y['ownerId'] if y['ownerId']
						instprops[:tags] = y['tagSet'] if y['tagSet']
						instprops[:network_interfaces] = y['networkInterfaces'] if y['networkInterfaces'] != []
						instprops[:block_device_mapping] = y['blockDeviceMapping'] if y['blockDeviceMapping'] != []
						instprops[:monitoring_enabled] = y['monitoring']['state'].to_s

						# lookup user_data and image_filter from our yaml file
						[ 'user_data', 'image_filter' ].each do |area|
							value = lookup_yaml(area,myname)
							if (value) 
								instprops[area.to_sym] = value
							end
						end

						if (instprops[:root_device_type] == 'ebs')
							instprops[:ebs_optimized] = y['ebsOptimized'].to_s
						end

						instprops.merge!(secprops)

						# list all instances with Names or are not terminted.
						if (instprops[:ensure] != 'terminated' || (instprops['tagSet'] && instprops['tagSet']['Name']))
							allinstances << instprops
						end
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

	def self.lookup_yaml(area,name)
		data = PuppetX::Practicalclouds::Storable::load(area)
		data[name]
	end

	#---------------------------------------------------------------------------------------------------
	# Ensure - handle all the running states...

	# ensureable replacement: Getter for custom 'ensure' property
	# manipulate the values which mean the same thing and when someone
	# is specifying an absent or terminated instance that does not exist.
	def ensure
		if (@resource[:ensure] == :terminated && @property_hash == {})
			return :terminated
		elsif (@resource[:ensure] == :absent && @property_hash == {})
			return :absent
		elsif (@resource[:ensure] == :absent && @property_hash[:ensure] =~ /^terminated/)
			return @resource[:ensure]
		elsif (@resource[:ensure] == :present && @property_hash[:ensure] =~ /^running/)
			return @resource[:ensure]
		else
			(@property_hash[:ensure]) ? @property_hash[:ensure] : :absent
		end
	end

	# defer the state change to the flush method...
	def ensure=(value)
		debug "I need to proces #{@resource[:name]} to #{value}"
		debug "state changes are handled in the flush method"
	end
		
	#---------------------------------------------------------------------------------------------------
	# Property Accessors 

	# getters... 

	# We want to return the value of the prefected property_hash but if it does not exist then
	# return the value of the resource so that each property does not try to update itself.
	%w(instance_id virtualization_type private_ip_address ip_address architecture disable_api_termination dns_name private_dns_name root_device_type launch_time owner_id network_interfaces availability_zone region image_id image_filter vpc_id subnet_id key_name instance_type kernel_id ramdisk_id user_data disable_api_temination instance_initiated_shutdown_behavior block_device_mapping source_dest_check security_group_ids security_group_names ebs_optimized monitoring_enabled tags).each do |property|
		define_method property do
			(@property_hash == {}) ? @resource[property.to_sym] : @property_hash[property.to_sym]
		end
	end

	# setters...

	# Define methods for strictly read-only properties...
	%w(instance_id virtualization_type private_ip_address ip_address architecture dns_name private_dns_name root_device_type launch_time owner_id network_interfaces vpc_id).each do |property|
		define_method "#{property}=" do
			fail "Sorry, you are not allowed to change the property READ-ONLY #{property} - please do not include it in your manifests."
		end
	end

	# Define properties which can be only be changed by terminating and recreating the instance
	%w(availability_zone region image_id image_filter subnet_id key_name).each do |property|
		define_method "#{property}=" do |value|
			schedule_change('terminated',property,value)
		end
	end

	# Define properties which can be changed by stopping an ebs instance and using modify_instance_attributes
	%w(instance_type kernel_id ramdisk_id).each do |property|
		define_method "#{property}=" do |value|
			schedule_change('stopped',property,value)
		end
		define_method "flush_#{property}=" do |value|
			modify_attribute(property,value)
		end
	end

	# Properties which can be changed at any time via modify_attribute
	%w(disable_api_temination instance_initiated_shutdown_behavior block_device_mapping ebs_optimized).each do |property|
		define_method "#{property}=" do |value|
			schedule_change('anytime',property,value)
		end
		define_method "flush_#{property}=" do |value|
			modify_attribute(property,value)
		end
	end

	# properties which can change at any time but need special flush methods which we will define below.
	%w(monitoring_enabled tags).each do |property|
		define_method "#{property}=" do |value|
			schedule_change('anytime',property,value)
		end
	end

	def flush_monitoring_enabled=(value)
		compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)	
		if (@resource[:monitoring_enabled] = :true)
			notice "Enabling monitoring on instance #{@resource[:name]}/#{@property_hash[:instance_id]}"
			response = compute.monitor_instances([ @property_hash[:instance_id] ])
			raise "Sorry, I couldn't enable monitoring!" if (response.status != 200)
		else
			notice "Disabling monitoring on instance #{@resource[:name]}/#{@property_hash[:instance_id]}"
			response = compute.unmonitor_instances([ @property_hash[:instance_id] ])
			raise "Sorry, I couldn't disable monitoring!" if (response.status != 200)
		end
	end

	def flush_tags=(value)
		debug "#{@resource[:name]} needs its tags updating..."
		debug "Requested tags (YAML):-\n#{@resource[:tags].to_yaml}"
		debug "Actual tags (YAML):-\n#{@property_hash[:tags].to_yaml}"
		assign_tags(@property_hash[:instance_id],value)
	end

	# Special changers and flush...

	def user_data=(value)
		schedule_change('stopped','user_data',value)
	end

	def flush_user_data=(value)
		enc=Base64.encode64(value)
		modify_attribute('user_data',enc)
		store_in_yaml('user_data',@property_hash[:name],value)
	end

	# VPC only can be changed whenever otherwise we need to terminate to change
	%w(security_group_ids).each do |property|
		define_method "#{property}=" do |value|
			if (@property_hash[:vpc_id])
				schedule_change('anytime','security_group_ids',value)
			else
				schedule_change('terminated','security_group_ids',value)
			end
		end
		define_method "flush_#{property}=" do |value|
			modify_attribute(property,value)
		end
	end

	# Properties whc
	%w(source_dest_check).each do |property|
      define_method "#{property}=" do |value|
         if (@property_hash[:vpc_id])
            schedule_change('anytime','source_dest_check',value)
         elsif(@resource[:subnet_id])
				schedule_change('terminated','source_dest_check',value)
			else
				fail "Sorry, you can only change the source_dest_check property on VPC instances (instances launched into a subnet)."
         end
      end
      define_method "flush_#{property}=" do |value|
         modify_attribute(property,value)
      end
   end

	# security_group_names need to be changed to ids in order
	# to be updated...
	def security_group_names=(value)
		if (@property_hash[:vpc_id])
			schedule_change('anytime','security_group_ids',lookup_security_groupids(value))
		else
			schedule_change('terminated','security_group_ids',lookup_security_groupids(value))
		end
	end

	#---------------------------------------------------------------------------------------------------
	# Helper Methods

	def exists?
		return nil if (!@property_hash)
		(@property_hash[:ensure]) ? 1 : nil
	end

	def myregion
		if (@property_hash[:region])
			return @property_hash[:region]
		elsif (@resource[:availability_zone])
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

		[ :ip_address, :architecture, :dns_name, :private_dns_name, :root_device_type, :launch_time, :virtualization_type, :owner_id, :network_interfaces ].each {|a|	
			info("Ignoring READONLY attribute #{a}") if (@resource[a])
		}

		# set up the options hash
		options_hash['Placement.AvailabilityZone'] = @resource[:availability_zone].to_s if @resource[:availability_zone]
		options_hash['Placement.GroupName'] = @resource[:placement_group_name].to_s if @resource[:placement_group_name]
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
		# ebs only options
		if (amirootdevicetype == 'ebs')
			options_hash['InstanceInitiatedShutdownBehavior'] = @resource[:instance_initiated_shutdown_behavior].to_s if @resource[:instance_initiated_shutdown_behavior]
			options_hash['EbsOptimized'] = @resource[:ebs_optimized] if @resource[:ebs_optimized]
		end

		# create the instance
		notice "Creating new ec2instance '#{@resource[:name]}' from image #{@resource[:image_id]}"
		info "#{@resource[:image_id]}: #{aminame}"
		debug "compute.run_instances(#{@resource[:image_id]},1,1,options_hash)"
		debug "options_hash (YAML):-\n#{options_hash.to_yaml}"

		response = compute.run_instances(@resource[:image_id],1,1,options_hash)	
		if (response.status == 200)
			debug "Instance created ok."
			sleep 5

			# Set the Name tag to the resource name
			if (!@resource[:tags])
				@resource[:tags] = { 'Name' => @resource[:name] }
			else
				@resource[:tags]['Name'] = @resource[:name]
			end
			instid = response.body['instancesSet'][0]['instanceId']
			info "Instance #{instid} created as #{@resource[:name]}"
			debug "Tagging instance #{instid} : #{@resource['tags']['Name']}"
			assign_tags(instid,@resource[:tags])

			# save the user_data and image_filter on the puppet master because we can't
			# access it through the amazon api
			store_in_yaml('user_data', @resource[:name], @resource[:user_data]) if @resource[:user_data]
			store_in_yaml('image_filter', @resource[:name], @resource[:image_filter]) if @resource[:image_filter]

			# optionally wait for the instance to be "running"
			optional_wait('running')

			# set the property hash in case we need to do something after this.
			@property_hash = { :ensure => 'pending', :instance_id => instid }
		else
			debug "The compute.run_instances call failed!"
			raise "I couldn't create the ec2 instance, sorry! API Error!"
		end
	end

	def destroy
		compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)
		if (@property_hash[:ensure] =~ /^(running|pending|stopped|stopping)$/)
			notice "Terminating ec2instance #{@property_hash[:name]} : #{@property_hash[:instance_id]}"
			debug "compute.terminate_instances(#{@property_hash[:instance_id]})"
			response = compute.terminate_instances(@property_hash[:instance_id])
			if (response.status != 200)
				raise "I couldn't terminate ec2 instance #{@property_hash[:instance_id]}"
			else
				optional_wait('terminated')
			end
		else
			notice "Instance #{@property_hash[:instance_id]} is #{@property_hash[:ensure]}"
		end

		# remove any associated user_data and image_filter from the aws yaml file
		remove_from_yaml('user_data',name)
		remove_from_yaml('image_filter',name)

		notice "Removing Name tag #{@property_hash[:name]} from #{@property_hash[:instance_id]}"
		debug "compute.delete_tags(#{@property_hash[:instance_id]},{ 'Name' => #{@property_hash[:name]}})"
		response = compute.delete_tags(@property_hash[:instance_id],{ 'Name' => @property_hash[:name]}) 
		if (response.status != 200)
			raise "I couldn't remove the Name tag from ec2 instance #{instance['instanceId']}"
		end
		# remove the property_hash because the instance no longer exists
		@property_hash={}
	end

	def stop
		compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)
		if (@property_hash[:ensure] =~ /^(running|pending)$/)
			if (@property_hash[:root_device_type] == 'ebs')
				notice "Stopping ec2instance #{@property_hash[:name]} : #{@property_hash[:instance_id]}"
				debug "compute.stop_instances([#{@property_hash[:instance_id]}])"
				response = compute.stop_instances([@property_hash[:instance_id]])
				if (response.status != 200)
					raise "I couldn't stop ec2 instance #{@property_hash[:instance_id]}"
				end
				optional_wait('stopped')
			else
				raise "Sorry. I'm not able to stop an instance-store instance"
			end
		end
	end

	def start
		compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)
		if (@property_hash[:ensure] =~ /^(stopping|stopped)$/)
			notice "Starting ec2instance #{@property_hash[:name]} : #{@property_hash[:instance_id]}"
			debug "compute.start_instances([#{@property_hash[:instance_id]}])"
			response = compute.start_instances([@property_hash[:instance_id]])
			if (response.status != 200)
				raise "I couldn't start ec2 instance #{@property_hash[:instance_id]}"
			end
			optional_wait('running')
		end
	end

	def modify_attribute(property,value)
		prop_to_api = { :instance_type => 'InstanceType.Value', :kernel_id => 'Kernel.Value', :ramdisk_id => 'Ramdisk.Value', :user_data => 'UserData.Value', :disable_api_temination => 'DisableApiTermination.Value', :instance_initiated_shutdown_behavior => 'InstanceInitiatedShutdownBehavior.Value', :block_device_mapping => 'BlockDeviceMapping.Value', :source_dest_check => 'SourceDestCheck.Value', :security_group_ids => 'GroupId', :ebs_optimized => 'EbsOptimized.Value' }
		compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)
		debug "compute.modify_instance_attribute(#{@property_hash[:instance_id]},{ #{prop_to_api[property.to_sym]} => #{value} })"
		response = compute.modify_instance_attribute(@property_hash[:instance_id], { prop_to_api[property.to_sym] => value })
		raise "Sorry, I couldn't modify the #{k} of ec2 instance #{@property_hash[:instance_id]}" if (response.status != 200)
	end

   def schedule_change(w,p,v)
      @my_changes = {} if (!@my_changes)
      if @my_changes[w]
         @my_changes[w][p] = v
      else
         @my_changes[w] = {p => v}
      end
   end

	# Flush - the brains of the outfit - it decides whether we need to be stopping, starting and 
	# making changes. 

	def flush
		debug "ec2instance - calling flush"

		present_state = @property_hash[:ensure].to_s
		desired_state = @resource[:ensure].to_s

		debug "Present state: #{present_state}"
		debug "Desired state: #{desired_state}"

		if (exists?)
			debug "Instance #{@resource[:name]} exists"
		else
			debug "Instance #{@resource[:name]} does not exist"
		end
		
		# do I need to terminate?
		if (exists?) 
			if (desired_state =~ /^(terminated|absent)$/) 
				notice "Instance #{@resource[:name]} is being terminated by ensure directive"
				destroy
				present_state='terminated'
			elsif (@my_changes && @my_changes['terminated'])
				notice "Instance #{@resource[:name]} is being terminated to make changes which can only be made by terminating and recreating"
				destroy
				present_state='terminated'
			elsif (@my_changes && @my_changes['stopped'] && @property_hash[:root_device_type] == 'instance_store')
				notice "Instance #{@resource[:name]} is and instance store instance and so is being terminated to make changes (which could be made whilst stopped for ebs backed instances)"
				destroy
				present_state='terminated'
			end
		end

		# do I need to stop?
		if (exists?)
			if (desired_state == 'stopped') 
				if (present_state =~ /^(running|pending)$/)
					if (@property_hash[:root_device_type] == 'ebs')
						notice "Instance #{@resource[:name]} is being stopped by ensure directive"
						stop 
						present_state='stopped'
					else
						fail "Sorry, you can only stop EBS backed instances."
					end
				elsif (present_state == 'stopping')
					notice "Instance #{@resource[:name]} is already stopping."
				end
			elsif (@my_changes && @my_changes['stopped'] && @property_hash[:root_device_type] == 'ebs')
				notice "Instance #{@resource[:name]} is being stopped to make required changes"
				stop 
				present_state='stopped'
			end
		end

		#do I need to make changes?
		if (@my_changes)
			if (exists?)
				if (present_state == 'stopped')
         		if (@my_changes['stopped'])
						max=(@resource[:max_wait]) ? @resource[:max_wait].to_i : 600
						wait_state(@property_hash[:name],'stopped',max)
            		@my_changes['stopped'].each do |k,v|
              			send("flush_#{k}=",v)
            		end
         		end
				end

         	if (@my_changes['anytime'])
            	@my_changes['anytime'].each do |k,v|
               	send("flush_#{k}=",v)
            	end
         	end
			end
		end

		#do I need to start?
		if (exists?)
			if (desired_state =~ /^(running|present)$/ && present_state == 'stopped')
				notice "Instance #{@resource[:name]} is being started"
				start 
			end
		end
			
		# do I need to be created?
		if (!exists?)
			if (desired_state =~ /^(present|running|stopped)$/)
				notice "Instance #{@resource[:name]} is being created."
				create
				if (desired_state == 'stopped')
					notice "The newly created instance #{@resource[:name]} needs to be stopped."
					stop
				end
			end
		end			
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
		max=max.to_i

		elapsed_wait=0
		check = instanceinfo(name)
		if ( check )
			info "Waiting for instance #{name} to be #{desired_state}"
			while ( check['instanceState']['name'] != desired_state && elapsed_wait < max ) do
				debug "instance #{name} is #{check['instanceState']['name']}"
				sleep 5
				elapsed_wait += 5
				check = instanceinfo(name)
			end
			if (elapsed_wait >= max)
				raise "Timed out waiting for name to be #{desired_state}"
			else
				info "Instance #{name} is #{desired_state}"
			end
		else
			raise "Sorry, I couldn't find instance #{name}"
		end
	end

	def optional_wait(desired_state)
		debug "optional_wait: #{desired_state}"
		wait=(@resource[:wait] == :true) ? :true : :false
		max=(@resource[:max_wait]) ? @resource[:max_wait].to_i : 600
		if (wait == :true)
			debug "calling wait_state(#{@resource[:name]},#{desired_state},#{max})"
			wait_state(@resource[:name],desired_state,max)
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
				if (tags['resourceId'] == resourceid)
					debug "read tag: #{tags['key']} = #{tags['value']}"
					mytags["#{tags['key']}"] = tags['value']
				end
			end
		else
			raise "I couldn't read the tags!"
		end

		# delete any tags which are not in the tag hash or havedifferent values
		if (mytags != {})
			deletetags={}
			mytags.each do |k,v|
				if (taghash[k] != v) 
					debug "Deleting tag #{k} = #{v} from #{resourceid}"
					deletetags[k] = v
					mytags.delete(k)
				end
			end
			if (deletetags != {})
				debug "compute.delete_tags(#{resourceid},deletetags)"
				debug "deletetags (YAML):-\n#{deletetags.to_yaml}"
				resp=compute.delete_tags(resourceid,deletetags)
				if (resp.status != 200)
					raise "I couldn't delete the tags!"
				end
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
			if (addtags != {})
				debug "compute.create_tags(#{resourceid},addtags)"
				debug "addtags (YAML):-\n#{addtags.to_yaml}"
				response = compute.create_tags(resourceid,addtags)
				if (response.status != 200)
					raise "I couldn't add tags to #{resourceid}"
				end
			end
		end
	end


   def lookup_security_groupids(groupnames)
      groupmap = {}
      compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)
      response = compute.describe_security_groups
      raise "Sorry, I could not read the security groups!" if (response.status != 200)
      response.body['securityGroupInfo'].each do |sg|
         groupmap[sg['groupName']]=sg['groupId']
      end

      groupids=[]
      groupnames.each do |name|
         if (groupmap[name])
            groupids << groupmap[name]
         else
            fail "Sorry, I could not find a group id for group name #{name}"
         end
      end
      groupids
   end

	# lookup an ami using a filter hash, e.g.
	# { 'is-public' => 'true', 'architecture' => 'x86_64', 'platform' => 'windows' }
	def lookup_image(filter)
      compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)
		debug "compute.describe_images(filter)\nFilter is:-\n#{filter.to_yaml}"
      response = compute.describe_images(filter)
      raise "Sorry, I could not read the images!" if (response.status != 200)
		if (response['imagesSet'].length == 0)
			raise "Sorry, I could not find any images matching the filter:-\n#{filter.to_yaml}"
		elsif (response['imagesSet'].length > 1)
			raise "Sorry, more than one image matches the filter:-\n#{filter.to_yaml}!\nPlease make the name more specific until it matches a single ami image"
		else
			response.body['imagesSet'][0]['imageId']
		end
	end

	# Functions for storing and retreiving data from the aws yaml file.

	def store_in_yaml(area,name,value)
		data = PuppetX::Practicalclouds::Storable::load(area)
		data[name] = value
		PuppetX::Practicalclouds::Storable::store(area,data)
	end

	def remove_from_yaml(area,name)
		data = PuppetX::Practicalclouds::Storable::load(area)
		if (data[name])
			data.delete(name)
			PuppetX::Practicalclouds::Storable::store(area,data)
		end
	end

end
