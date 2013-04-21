require 'rubygems'
require 'fog'
require 'facter'
require 'pp'

$debug=true
$allawsregions=['us-east-1','us-west-1','us-west-2','eu-west-1','ap-southeast-1','ap-southeast-2','ap-northeast-1','sa-east-1']

Puppet::Type.type(:awscompute).provide(:fog) do
	desc "The AWS Provider which implements the ec2instance type."

	# Only allow the provider if fog is installed.
	commands :fog => 'fog'

   def self.instances
		@yamlfile = "#{Puppet[:confdir]}/aws.yaml"
		@aws_access_key_id = nil
		@aws_secret_access_key = nil
		@regions = nil

		# load in an awsaccess object for connecting to AWS.
      return [] if (!File.exists?(@yamlfile))
      cfghash = YAML::load(File.open(@yamlfile))
		if (cfghash.length >=1) then
			puts "The configs available are:-"
			pp cfghash
			# choose the default access for retrieving a list of instances
			if (cfghash['default']) then
				@aws_access_key_id = cfghash['default'][:aws_access_key_id] if (cfghash['default'].keys.include?(:aws_access_key_id))
				@aws_secret_access_key = cfghash['default'][:aws_secret_access_key] if (cfghash['default'].keys.include?(:aws_secret_access_key))
				@regions = cfghash['default'][:regions] if (cfghash['default'].keys.include?(:regions))
			else
				# no default config, pick the first one
				@aws_access_key_id = cfghash[0][:aws_access_key_id] if (cfghash[0].keys.include?(:aws_access_key_id))
				@aws_secret_access_key = cfghash[0][:aws_secret_access_key] if (cfghash[0].keys.include?(:aws_secret_access_key))
				@regions = cfghash[0][:regions] if (cfghash[0].keys.include?(:regions))
         end
		end
		if (!@aws_access_key_id || !@aws_secret_access_key)
			puts "Without access keys, I can't do much"
			return []
		end
		puts "Using AWS Configs access=#{@aws_access_key_id}, secret=#{@aws_secret_access_key} and regions=#{@regions}"
		@regions = $allawsregions if (!@regions)
		puts "Looking for compute instances in #{@regions}"
		
		# get a list of instances in all of the regions we are configured for.
		allinstances=[]
		@regions.each {|reg|	
			compute = Fog::Compute.new(:provider => 'aws', :aws_access_key_id => @aws_access_key_id, :aws_secret_access_key => @aws_secret_access_key, :region => "#{reg}")	
			puts "describe_instances for #{reg}"
			resp = compute.describe_instances
      	if (resp.status == 200)
         	# check through the instances looking for one with a matching Name tag
				puts "response ok"
         	resp.body['reservationSet'].each { |x|
            	x['instancesSet'].each { |y|
               	if (y['tagSet']['Name'])
							puts "Found #{y['tagSet']['Name']} in #{reg}"
							allinstances << {	:name => y['tagSet']['Name'],
													:ensure => :present,
													:region => reg,
													:availability_zone => y['placement']['availabilityZone'] }
						else
							puts "Found instance #{y['instanceId']}"
							allinstances << { :name => y['instanceId'],
													:ensure => :present,
													:region => reg,
													:availability_zone => y['placement']['availabilityZone'] }
               	end
            	}
         	}
			else
				raise "Sorry, I could not retrieve a list of instances from #{region}!"
			end
		}
	
		# return the list of instances
		puts "I found these instances..."
		pp allinstances

		puts "creating puppet objects..."
		pp allinstances.map {|x| new(x)}
		allinstances.map {|x| new(x)}
	end

	def region=(value)
		puts "Sorry you can't change the region of an ec2 instance without destorying it"
	end

	def availability_zone=(value)
		puts "Sorry you can't change the region of an ec2 instance without destorying it"
	end

   #def self.prefetch(resources)
   #   configs = instances
   #   resources.keys.each do |name|
   #      if provider = configs.find{ |conf| conf.name == name}
   #         resources[name].provider = provider
   #      end
   #   end
   #end

	mk_resource_methods

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
		#if (@resource[:availability_zone]) then
		#	region = @resource[:availability_zone].gsub(/.$/,'')
		#elsif (@resource[:region]) then
		#	region = @resource[:region]
		#end
		#compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")
		#instance = instanceinfo(compute,@resource[:name])
		#if (instance)
		#	notice "Terminating ec2 instance #{@resource[:name]} : #{instance['instanceId']}"
		#else
		#	raise "Sorry I could not lookup the instance with name #{@resource[:name]}" if (!instance)
		#end
		#response = compute.terminate_instances(instance['instanceId'])
		#if (response.status != 200)
		#	raise "I couldn't terminate ec2 instance #{instance['instanceId']}"
		#else
		#	if (@resource[:wait] == :true)
		#		wait_state(compute,@resource[:name],'terminated',@resource[:max_wait])
		#	end
		#	notice "Removing Name tag #{@resource[:name]} from #{instance['instanceId']}"
		#	response = compute.delete_tags(instance['instanceId'],{ 'Name' => @resource[:name]}) 
		#	if (response.status != 200)
		#		raise "I couldn't remove the Name tag from ec2 instance #{instance['instanceId']}"
		#	end
		#end
	end

	def exists?
		@yamlfile = "#{Puppet[:confdir]}/aws.yaml"
		#if (@resource[:availability_zone]) then
		#	region = @resource[:availability_zone].gsub(/.$/,'')
		#elsif (@resource[:region]) then
		#	region = @resource[:region]
		#end
		#compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")
		#instanceinfo(compute,@resource[:name])
		@property_hash[:ensure] == :present
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
