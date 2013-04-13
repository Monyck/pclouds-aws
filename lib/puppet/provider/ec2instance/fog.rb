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
				raise "ec2instance[aws]->create: Sorry, you must include \"#{param}\" when defining an ec2instance!"
			end
		}
		# copy simple parameters to the fog_options hash..
		simple_params.keys.each {|param|
			if (@resource[param])
				notice "Adding fog parameter #{simple_params[param].to_s} : #{@resource[param]}"
				fog_options[simple_params[param].to_s]=@resource[param]		
			end
		}

		# Work out region and connect to AWS...
		if (@resource[:availability_zone]) then
			region = @resource[:availability_zone].gsub(/.$/,'')
		elsif (@resource[:region]) then
			region = @resource[:region]
		end
		compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")
		notice "ec2instance[aws]->create: Region is #{region}\n" if $debug

		# process the complex params which need processing into fog options...
		# each option is implemented as it's own method which maps
		# parameters into fog_options 
		#complex_params.each {|param|
		#	if (@resource[param])
		#		notice "ec2instance[aws]->create: processing parameter #{param}\n" if $debug
		#		self.send(:"param_#{param}",compute,@resource,fog_options)
		#	end
		#}

		# start the instance
		response = compute.run_instances(@resource[:image_id],@resource[:min_count].to_i,@resource[:max_count].to_i,fog_options)	
		if (response.status == 200)
			instid = response.body['instancesSet'][0]['instanceId']
			notice "ec2instance[aws]->create: booting instance #{instid}.\n" if $debug
			response = compute.create_tags(instid,{ :Name => @resource[:name] })
			if (response.status == 200)
				notice "ec2instance[aws]->create: I tagged #{instid} with Name = #{@resource[:name]}\n" if $debug
			else
				raise "ec2instance[aws]->create: I couldn't tag #{instid} with Name = #{@resource[:name]}, sorry! API Error!"
			end
			if (@resource[:wait] == :true)
				# Wait for my instance to start...
				elapsed_wait=0
				check = instanceinfo(compute,@resource[:name])
				if ( check && check['instanceState']['name'] == "pending" )
					notice "Waiting for #{@resource[:name]} tp start up..."
					while ( check['instanceState']['name'] != "running" && elapsed_wait < @resource[:max_wait]  ) do
						notice "ec2instance[aws]->create: #{@resource[:name]} is #{check['instanceState']['name']}\n" if $debug
						sleep 5
						elapsed_wait += 5
						check = instanceinfo(compute,@resource[:name])
					end
					if (elapsed_wait >= @resource[:max_wait])
						raise "ec2instance[aws]->create: Timed out waiting for #{@resource[:name]} to start up!"
					else
						sleep 5  # allow aws to propigate the fact
						notice "ec2instance[aws]->create: #{@resource[:name]} is #{check['instanceState']['name']}\n" if $debug
					end
				elsif (check && check['instanceState']['name'] != "running" )
					raise "ec2instance[aws]->create: Sorry, #{@resource[:name]} is #{check['instanceState']['name']} and I expected it to be 'pending'"
				end
			end
		else
			raise "ec2instance[aws]->create: I couldn't create the ec2instance, sorry! API Error!"
		end
	end

	def destroy
		# remove an existing ec2instance
		notice "The man would stop the ec2instance..."
	end

	def exists?
		notice "Looking for an instance of Name #{@resource['name']}" if ($debug)
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
			raise "ec2instance[aws]->instanceinfo: I couldn't list the instances"
		end
		false	
	end	

end
