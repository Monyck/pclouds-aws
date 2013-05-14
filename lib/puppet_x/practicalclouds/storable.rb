require 'yaml'
require 'pp'

# This helper class manages and shares connections to AWS so that
# provider functions don't all have to open their own connections

module PuppetX
	module Practicalclouds
		module Storable

			YAMLFILE="#{Puppet[:confdir]}/aws.yaml"

			def self.load(type)
				if File.exists?(YAMLFILE)
					hash = {}
					yamlf = YAML::load(File.open(YAMLFILE))
					if (yamlf[type])
						hash = yamlf[type].clone
					end
				end
				hash
			end

			def self.store(type,hash)
				outhash = {}
				if File.exists?(YAMLFILE)
					outhash = YAML::load(File.open(YAMLFILE))
				end
				outhash[type] = hash
				File.open(YAMLFILE,'w+') {|f| f.write(outhash.to_yaml) }
			end
		end
	end
end	
