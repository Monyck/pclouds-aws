require 'rubygems'
require 'fog'
require 'facter'
require 'pp'

$debug=true

Puppet::Type.type(:awsconfig).provide(:fog) do
	desc "The awsconfig type allows us to configure AWS access and secret keys from within puppet.  It also allow us to define which regions we wish to connect to and ensure unqiueness across (by default we ensure a unique Name across all known regions of Amazon AWS, change to restrict it to run within a subset of regions. "

	# Only allow the provider if fog is installed.
	commands :fog => 'fog'

	def self.instances
		configfile="#{Puppet[:confdir]}/awsconfigs.yaml"
		return [] if (!File.exists?(configfile))
		confighash = YAML::load(File.open(configfile))
		confighash.keys.map {|n|
			settings = confighash[n]
			settings[:name] = n
			settings[:ensure] = :present
			new(settings) 
		}
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

	def aws_access_key_id=(value)
		@updated_properties = true
		@property_hash[:aws_access_key_id] = value
	end
	
	def aws_secret_access_key=(value)
		@updated_properties = true
		@property_hash[:aws_secret_access_key] = value
	end
	
	def regions=(value)
		@updated_properties = true
		@property_hash[:regions] = value
	end

	def create
		@updated_properties = true
		@property_hash[:ensure] = :present
	end

	def destroy
		@updated_properties = true
		@property_hash[:ensure] = :absent
	end

	def flush
		puts "entered flush..."
		puts @updated_properties
		if @updated_properties == true
			configshash = {}
			if (File.exists?(Puppet[:confdir] + '/awsconfigs.yaml'))
				puts "loading yaml file..."
				configshash = YAML::load(File.open(Puppet[:confdir] + '/awsconfigs.yaml'))
			else
				puts "yaml file does not exist"
			end
			if (@property_hash[:ensure] == :present)
				puts "Adding or updating configs..."
				configshash[@property_hash[:name]] = @property_hash
				configshash[@property_hash[:name]].delete(:name)
			else
				puts "Removing configs..."
				configshash.delete(@property_hash[:name])
			end
			puts "Saving the following configshash:-"
			pp configshash
			File.open(Puppet[:confdir] + '/awsconfigs.yaml','w+') {|f| f.write(configshash.to_yaml) }
		else
			puts "I don't need to make any updates.."
		end
	end

	def exists?
		@property_hash[:ensure] == :present
	end
end
