require 'rubygems'
require 'fog'
require 'facter'
require 'pp'

$debug=true

Puppet::Type.type(:awsaccess).provide(:fog) do
	desc "The awsaccess resource allows us to configure AWS access and secret keys from within puppet.  It also allow us to define which regions we wish to connect to and ensure unqiueness across (by default we ensure a unique Name across all known regions of Amazon AWS, change to restrict it to run within a subset of regions. "

	# Only allow the provider if fog is installed.
	commands :fog => 'fog'

	def self.instances
		@yamlfile = "#{Puppet[:confdir]}/aws.yaml"

		return [] if (!File.exists?(@yamlfile))
		chash = YAML::load(File.open(@yamlfile))
		chash.keys.map {|n|
			settings = chash[n]
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
		atts = [ :name, :ensure, :regions, :aws_access_key_id, :aws_secret_access_key ]
		atts.each {|att| @property_hash[att] = @resource[att] if (@resource[att])}
		@updated_properties = true
		end

	def destroy
		@updated_properties = true
		@property_hash[:ensure] = :absent
		end

	def flush
		if (@updated_properties == true)
			configshash = {}
			if (File.exists?(@yamlfile))
				configshash = YAML.load(File.read(@yamlfile))
			end
			if (@property_hash[:ensure] == :present)
				configshash[@property_hash[:name]] = @property_hash
				configshash[@property_hash[:name]].delete(:name)
			else
				configshash.delete(@property_hash[:name])
			end
			File.open(@yamlfile,'w+') {|f| f.write(configshash.to_yaml) }
		end
	end

	def exists?
		@yamlfile = "#{Puppet[:confdir]}/aws.yaml"
      #davetest = @resource.catalog.resources
      #pp davetest
		@property_hash[:ensure] == :present
		end
end
