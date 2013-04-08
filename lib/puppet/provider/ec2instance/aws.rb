require 'rubygems'
require 'fog'
require 'facter'

$debug=true

Puppet::Type.type(:ec2instance).provide(:aws) do
	desc "The AWS Provider which implements the ec2instance type."

	# Only allow the provider if fog is installed.
	commands :fog => '/usr/bin/fog'

	def create
		required_params = [ :Name, :ImageId,:MinCount, :MaxCount ]
		simple_params = [ :InstanceType, :KeyName, :KernelId, :RamdiskId, :MonitoringEnabled, :SubnetId, :PrivateIpAddress, :DisableApiTermination, :InstanceInitiatedShutdownBehavior, :EbsOptimized ]
		#complex_params = [ :SecurityGroupNames, :SecurityGroupIds, :UserData, :UserDataBase64, :BlockDeviceMapping ]
		fog_options = {}

		# check required parameters...
  		required_params.each {|param|
    		if (!resource[param])
      		notice "Missing required option #{param}!"
      		raise "ec2instance[aws]->create: Sorry, you must include \"#{param}\" when defining an ec2instance!"
    		end
  		}
		# copy simple parameters to the fog_options hash..
  		simple_params.each {|param|
    		if (resource[param])
				notice "Adding fog option #{param} : #{resource[param]}"
				fog_options[param]=resource[param]		
    		end
  		}

		# Work out region and connect to AWS...
		if (resource[:AvailabilityZone]) then
			region = resource[:AvailabilityZone].gsub(/.$/,'')
		elsif (resource[:Region]) then
			region = resource[:Region]
		end
		Fog.mock!
		compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")
		notice "ec2instance[aws]->create: Region is #{region}\n" if $debug

		# process the complex params which need processing into fog options...
		# each option is implemented as it's own method which maps
		# parameters into fog_options 
  		#complex_params.each {|param|
    	#	if (resource[param])
		#		notice "ec2instance[aws]->create: processing parameter #{param}\n" if $debug
		#		self.send(:"param_#{param}",compute,resource,fog_options)
    	#	end
  		#}

		# start the instance
		response = compute.run_instances(resource[:ImageID],resource[:MinCount].to_i,resource[:MaxCount].to_i,fog_options)	
		if (response.status == 200)
			instid = response.body[instancesSet][0]['instanceId']
			notice "ec2instance[aws]->create: booting instance #{instid}.\n" if $debug
			response = compute.create_tags(instid,{ :Name => resource[:Name] })
			if (response.status == 200)
				notice "ec2instance[aws]->create: I tagged #{instid} with Name = #{resource[:Name]}\n" if $debug
			else
				raise "ec2instance[aws]->create: I couldn't tag #{instid} with Name = #{resource[:Name]}, sorry! API Error!"
			end
			# Wait for my instance to start...
         check = instanceinfo(compute,resource[:Name])
			if ( check && check['instanceState']['name'] == "pending" )
				notice "Waiting for #{resource[:Name]} tp start up..."
         	while ( check['instanceState']['name'] != "running" ) do
            	notice "ec2instance[aws]->create: #{resource[:Name]} is #{check['instanceState']['name']}\n" if $debug
            	sleep 5
            	check = instanceinfo(compute,resource[:Name])
         	end
         	sleep 5  # allow aws to propigate the fact
         	notice "ec2instance[aws]->create: #{resource[:Name]} is #{check['instanceState']['name']}\n" if $debug
			elsif (check && check['instanceState']['name'] != "running" )
				raise "ec2instance[aws]->create: Sorry, #{resource[:Name]} is #{check['instanceState']['name']} and I expected it to be 'pending'"
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
		if (resource[:AvailabilityZone]) then
			region = resource[:AvailabilityZone].gsub(/.$/,'')
		elsif (resource[:Region]) then
			region = resource[:Region]
		end
		compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")
		instanceinfo(compute,resource[:Name])
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
		nil
	end	

	# Lookup an instances Name given it's instanceId
	def lookupname(compute,id)
		if ( id =~ /i-/ )
			resp = compute.describe_instances	
			if (resp.status == 200)
				# check through the instances looking for one with a matching instanceId
				resp.body['reservationSet'].each { |x|
					x['instancesSet'].each { |y| 
						if ( y['instanceId'] == id )
							if ( y['tagSet']['Name'] != nil )
								notice "#{id} is #{y['tagSet']['Name']}\n" if $debug

								return y['tagSet']['Name']
							else
								raise "ec2instance[aws]->myname: #{id} does not have a Name tag!  Sorry, I NEED aws objects to have Name tags in order to work!"
							end
						end
					}
				}
			else
				raise "ec2instance[aws]->lookupname: I couldn't list the instances!"
			end
		else
			raise "ec2instance[aws]->lookupname: Sorry, #{id} does not look like an aws instance id!"
		end
		nil
	end

end
