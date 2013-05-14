require 'yaml'

# This helper class manages and shares connections to AWS so that
# provider functions don't all have to open their own connections

module PuppetX
	module Practicalclouds

	   # yamlhash - extends hash to load and save values from a selected yaml file
		# (e.g. /etc/puppet/aws.yaml)

		module storable
			@yamlfile="#{Puppet[:confdir]}/aws.yaml"
			
			def load(type)
				if File.exists?(@yamlfile)
					hash = {}
            	yamlf = YAML::load(File.open(@yamlfile))
					if (yamlf[type])
						hash = yamlf[type].clone
					end
         	end
				hash
			end
				
			def store(type)
				outhash = {}
				if File.exists?(@yamlfile)
            	outhash = YAML::load(File.open(@yamlfile))
				end
				outhash[type] = self
				File.open(@yamlfile,'w+') {|f| f.write(outhash.to_yaml) }
			end
		end
				
	end
end	
