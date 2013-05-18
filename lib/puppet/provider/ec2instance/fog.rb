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
						instprops[:owner_id] = y['ownerId'] if y['ownerId']
						instprops[:tags] = y['tagSet'] if y['tagSet']
						instprops[:network_interfaces] = y['networkInterfaces'] if y['networkInterfaces'] != []
						instprops[:block_device_mapping] = y['blockDeviceMapping'] if y['blockDeviceMapping'] != []
						instprops[:monitoring_enabled] = y['monitoring']['state'].to_s

						# lookup user_data from our yaml file
						udata = lookup_user_data(myname)
						if (udata) 
							instprops[:user_data] = udata
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

	def self.lookup_user_data(name)
		udata = PuppetX::Practicalclouds::Storable::load('user_data')
		udata[name]
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

	# ensurable replacement: decide what to do when requested to change between our states.
	# Call our exists?, create and destory methods to do the work as though we are ensurable.
	def ensure=(value)
		debug "I need to proces #{@resource[:name]} to #{value}"
		case value.to_s
		when 'pending','shutting-down'
			fail("Sorry! You are not allowed to set ec2instances into the 'pending' or 'stutting-down' states.")
		when 'terminated', 'absent'
			if (exists?)
				case @property_hash[:ensure]
				when 'pending','running','stopping','stopped'
					destroy
				when 'shutting-down'
					info "Instance #{@property_hash[:name]} is already shutting-down."
				else
					fail("I don't know how change #{@property_hash[:name]} from #{@property_hash[:ensure]} to #{value}")
				end
			end
		when 'running','present'
			if (exists?)
				case @property_hash[:ensure]
				when 'shutting-down'
					debug "#{@property_hash[:name]} is shutting_down"
				when 'terminated'
					debug "Found a terminated instance #{property_hash[:instance_id]} with name #{@property_hash[:name]} : removing and starting a new one"
					destroy
					create
				when 'stopped','stopping'
					start
				when 'pending'
					info "Instance #{@property_hash[:name]} : #{@property_hash[:instance_id]} is already starting up"
				else
					fail("I don't know how change #{@property_hash[:name]} from #{@property_hash[:ensure]} to #{value}")
				end
			else
				debug "No instance #{@resource[:name]} exists, create a new one.."
				create
			end
		when 'stopped'
			if (exists?)
				case @property_hash[:ensure]
				when 'terminated'
					fail "Sorry, I can't stop a terminated instance"	
				when 'shutting-down'
					info "Instance #{@resource[:name]} is already shutting-down, try stopping it once running."
				when 'stopping'
					info "Instance #{@resource[:name]} is already stopping."
				when 'running','pending'
					stop
				end
			else
				fail("Sorry, can't stop non-existent ec2instance #{@resource[:name]}")
			end
		else
			fail "I'm lost as to how I ensure ec2instance is '#{value}'"
		end
	end

	#---------------------------------------------------------------------------------------------------
	# Property Accessors 

	# getters... 

	# We want to return the value of the prefected property_hash but if it does not exist then
	# we want to return the value of the resource so that each property does not try to update itself.
	%w(instance_id virtualization_type private_ip_address ip_address architecture dns_name private_dns_name root_device_type launch_time owner_id network_interfaces availability_zone region image_id subnet_id key_name instance_type kernel_id ramdisk_id user_data disable_api_temination instance_initiated_shutdown_behavior block_device_mapping source_dest_check security_group_ids security_group_names ebs_optimized monitoring_enabled tags).each do |property|
		define_method property do
			(@property_hash == {}) ? @resource[property.to_sym] : @property_hash[property.to_sym]
		end
	end

	# setters...

	# Define methods for strictly read-only properties...
	%w(instance_id virtualization_type private_ip_address ip_address architecture dns_name private_dns_name root_device_type launch_time owner_id network_interfaces).each do |property|
		define_method "#{property}=" do
			fail "Sorry, you are not allowed to change the property #{property} - do not use it in your manifests."
		end
	end

	# Define properties which can be only be changed by terminating and recreating the instance
	%w(availability_zone region image_id subnet_id key_name ).each do |property|
		define_method "#{property}=" do |value|
			if (@change_when_terminated)
				@change_when_terminated[property.to_sym] = value
			else
				@change_when_terminated={property.to_sym => value}
			end
		end
	end

	# Define properties which can be changed by stopping an ebs instance and using modify_instance_attributes
	%w(instance_type kernel_id ramdisk_id disable_api_temination instance_initiated_shutdown_behavior block_device_mapping source_dest_check security_group_ids security_group_names ebs_optimized).each do |property|
		define_method "#{property}=" do |value|
			if (@change_when_stopped)
				@change_when_stopped[property.to_sym] = value
			else
				@change_when_stopped={property.to_sym => value}
			end
		end
		define_method "flush_#{property}=" do |value|
			modify_attribute(property,value)
		end
	end

	# Properties which require unqiue handling 
	%w(monitoring_enabled tags).each do |property|
		define_method "#{property}=" do |value|
			if (@change_whenever)
				@change_whenever[property.to_sym] = value
			else
				@change_whenever={property.to_sym => value}
			end
		end
	end

	# User data needs it own special setters..

	def user_data=(value)
		if (@change_when_stopped)
			@change_when_stopped[property.to_sym] = value
		else
			@change_when_stopped={property.to_sym => value}
		end
	end

	def flush_user_data=(value)
		enc=Base64.encode64(value)
		modify_attribute('user_data',enc)
		save_user_data(@property_hash[:name],value)
	end

	# Property setters which get called by flush

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

	#---------------------------------------------------------------------------------------------------
	# Helper Methods

	def exists?
		debug "Checking if #{@resource[:name]} exists"
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
			debug "Naming instance #{instid} : #{@resource['tags']['Name']}"
			assign_tags(instid,@resource[:tags])

			# save the user_data on the puppet master because we can't
			# access it through the amazon api
			save_user_data(@resource[:name], @resource[:user_data]) if @resource[:user_data]

			# optionally wait for the instance to be "running"
			optional_wait('running')
		else
			debug "The compute.run_instances call failed!"
			raise "I couldn't create the ec2 instance, sorry! API Error!"
		end
	end

	def destroy
		compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)
		if (@property_hash[:ensure] =~ /^(running|pending|stopped|stopping)$/)
			notice "Terminating ec2 instance #{@property_hash[:name]} : #{@property_hash[:instance_id]}"
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

		# remove any associated user data from the aws yaml file
		remove_user_data(@property_hash[:name])

		notice "Removing Name tag #{@property_hash[:name]} from #{@property_hash[:instance_id]}"
		debug "compute.delete_tags(#{@property_hash[:instance_id]},{ 'Name' => #{@property_hash[:name]}})"
		response = compute.delete_tags(@property_hash[:instance_id],{ 'Name' => @property_hash[:name]}) 
		if (response.status != 200)
			raise "I couldn't remove the Name tag from ec2 instance #{instance['instanceId']}"
		end
		# delete the property_hash - this instance no longer exists.
		@property_hash = {}
	end

	def stop
		compute = PuppetX::Practicalclouds::Awsaccess.connect(myregion,myaccess)
		if (@property_hash[:ensure] =~ /^(running|pending)$/)
			if (@property_hash[:root_device_type] == 'ebs')
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

	# Flush - write out the changes which require a restart or applying whilst stopped.
	def flush
		# If we need to terminate the instance then all changes will be made by creating the new instance.
		if (@change_when_terminated || (@change_when_stopped && @property_hash[:root_device_type] == 'instance_store'))
			notice "Instance #{@resource[:name]} is being terminated and re-created in order to make the following property changes:-\n#{@change_when_terminated.merge(@change_when_stopped).to_yaml}"
			destroy
			create
			return
		end

		# If the instance wasn't terminated then we might need to apply some other changes when stopped.
		if (@change_when_stopped && @property_hash[:root_device_type] == 'ebs')
			if (@property_hash[:ensure] =~ /^(running|pending)$/)
				notice "Ebs instance #{@resource[:name]} is being stopped to make property changes."
				stop
				max=(@resource[:max_wait]) ? @resource[:max_wait].to_i : 600
				wait_state(@property_hash[:name],'stopped',max)
			end
		end

		notice "Making the following property changes to Instance #{@resource[:name]}:-\n#{@change_when_stopped.merge(@change_whenever).to_yaml}"
		@change_when_stopped.merge(@change_whenever).each do |k,v|
			send("flush_#{k}=",v)
		end

		if (@property_hash[:ensure] =~ /^(running|pending)$/)
			notice "Ebs instance #{@resource[:name]} is being started again."
			start
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

	def optional_wait(desired_state)
		wait=(@resource[:wait] == :true) ? :true : :false
		max=(@resource[:max_wait]) ? @resource[:max_wait].to_i : 600
		if (wait == :true)
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

	# Functions for storing and retreiving user_data from the 
	# aws yaml file.

	def save_user_data(name,data)
		udata = PuppetX::Practicalclouds::Storable::load('user_data')
		udata[name] = data
		PuppetX::Practicalclouds::Storable::store('user_data',udata)
	end

	def remove_user_data(name)
		udata = PuppetX::Practicalclouds::Storable::load('user_data')
		if (udata[name])
			udata.delete(name)
			PuppetX::Practicalclouds::Storable::store('user_data',udata)
		end
	end

end
