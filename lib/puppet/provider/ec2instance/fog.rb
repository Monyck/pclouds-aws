require 'rubygems'
require 'fog'
require 'facter'
require 'pp'

$debug=true

Puppet::Type.type(:ec2instance).provide(:fog) do
	desc "The AWS Provider which implements the ec2instance type."

	# Only allow the provider if fog is installed.
	commands :fog => 'fog'

	def create
		notice "Creating new ec2 instance with name #{@resource[:name]}"
		required_params = [ :name, :image_id, :min_count, :max_count ]
		simple_params = { :instance_type => 'InstanceType', 
			:key_name => 'KeyName', 
			:kernel_id => 'KeyName', 
			:ramdisk_id => 'RamdiskId', 
			:monitoring_enabled => 'Monitoring.Enabled', 
			:subnet_id => 'SubnetId', 
			:private_ip_address => 'PrivateIpAddress', 
			:disable_api_termination => 'DisableApiTermination', 
			:ebs_optimized => 'EbsOptimized', 
			:user_data => 'UserData' }
		#complex_params = [ :security_group_names, :security_group_ids, :block_device_mapping ]
		fog_options = {}

		# check required parameters...
		required_params.each {|param|
			if (!@resource[param])
				notice "Missing required attribute #{param}!"
				raise "Sorry, you must include \"#{param}\" when defining an ec2instance!"
			end
		}
		# copy simple parameters to the fog_options hash..
		simple_params.keys.each {|param|
			if (@resource[param])
				notice "Adding fog parameter #{simple_params[param].to_s} : #{@resource[param]}"
				fog_options[simple_params[param].to_s]=@resource[param]		
			end
		}

		if (@resource[:availability_zone]) then
			region = @resource[:availability_zone].gsub(/.$/,'')
		elsif (@resource[:region]) then
			region = @resource[:region]
		end
		compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")
		notice "Region is #{region}" if $debug

		# process the complex params which need processing into fog options...
		# each option is implemented as it's own method which maps
		# parameters into fog_options 
		#complex_params.each {|param|
		#	if (@resource[param])
		#		notice "Processing parameter #{param}\n" if $debug
		#		@resource.send(:"param_#{param}",compute,@resource,fog_options)
		#	end
		#}

		# start the instance
		response = compute.run_instances(@resource[:image_id],@resource[:min_count].to_i,@resource[:max_count].to_i,fog_options)	
		if (response.status == 200)
			sleep 5
			instid = response.body['instancesSet'][0]['instanceId']
			notice "Tagging instance #{instid} with Name #{@resource[:name]}." if $debug
			response = compute.create_tags(instid,{ :Name => @resource[:name] })
			if (response.status != 200)
				raise "I couldn't tag #{instid} with Name = #{@resource[:name]}"
			end
			if (@resource[:wait] == :true)
				wait_state(compute,@resource[:name],'running',@resource[:max_wait])
			end
		else
			raise "I couldn't create the ec2 instance, sorry! API Error!"
		end
	end

	def destroy
		if (@resource[:availability_zone]) then
			region = @resource[:availability_zone].gsub(/.$/,'')
		elsif (@resource[:region]) then
			region = @resource[:region]
		end
		compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")
		instance = instanceinfo(compute,@resource[:name])
		if (instance)
			notice "Terminating ec2 instance #{@resource[:name]} : #{instance['instanceId']}"
		else
			raise "Sorry I could not lookup the instance with name #{@resource[:name]}" if (!instance)
		end
		response = compute.terminate_instances(instance['instanceId'])
		if (response.status != 200)
			raise "I couldn't terminate ec2 instance #{instance['instanceId']}"
		else
			if (@resource[:wait] == :true)
				wait_state(compute,@resource[:name],'terminated',@resource[:max_wait])
			end
			notice "Removing Name tag #{@resource[:name]} from #{instance['instanceId']}"
			response = compute.delete_tags(instance['instanceId'],{ 'Name' => @resource[:name]}) 
			if (response.status != 200)
				raise "I couldn't remove the Name tag from ec2 instance #{instance['instanceId']}"
			end
		end
	end

	def exists?
		if (@resource[:availability_zone]) then
			region = @resource[:availability_zone].gsub(/.$/,'')
		elsif (@resource[:region]) then
			region = @resource[:region]
		end
		compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")
		instanceinfo(compute,@resource[:name])
	end

	# for looking up information about an ec2 instance given the Name tag
	def instanceinfo(compute,name)
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

	# generic method to wait for an instance state...
	def wait_state(compute,name,desired_state,max)
		elapsed_wait=0
		check = instanceinfo(compute,name)
		if ( check )
			notice "Waiting for instance #{name} to be #{desired_state}"
			while ( check['instanceState']['name'] != desired_state && elapsed_wait < max ) do
				notice "instance #{name} is #{check['instanceState']['name']}" if $debug
				sleep 5
				elapsed_wait += 5
				check = instanceinfo(compute,name)
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

end
