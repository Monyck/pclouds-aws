require 'fog'

# This helper class manages and shares connections to AWS so that
# provider functions don't all have to open their own connections

module PuppetX
	module Practicalclouds
		class Awsaccess
			@@yamlfile="#{Puppet[:confdir]}/aws.yaml"
			@@credentials = {}
			@@connections = {}

			# return a list of regions from an aws credential 
			def self.regions(name)
				if (@@credentials == {})
					@@credentials = YAML::load(File.open(@@yamlfile))
				end
				if (@@credentials[name])
					return (@@credentials[name][:regions]) ? @@credentials[name][:regions] : []
				else
					raise "Sorry, awsaccess credential '#{name}' does not exist!"
				end
			end

			# Connect to an AWS region using a specific credential
			def self.connect(reg,name)
				# return an existing connection...
				if (@@connections[reg])
					if (@@connections[reg][name]) 
						return @@connections[reg][name]
					end
				end

				# make sure we have the credentials loaded and make a new connection
				if (@@credentials == {})
					@@credentials = YAML::load(File.open(@@yamlfile))
				end
				if (@@credentials[name])
					if (@@credentials[name][:regions] && !@@credentials[name][:regions].member?(reg))
						raise "Sorry, Awsaccess '#{name}' is not allowed in region '#{reg}'"
					elsif (!@@credentials[name][:aws_access_key_id] || !@@credentials[name][:aws_secret_access_key])
						raise "Sorry, You must have both an aws_access_key_id and aws_secret_access_key in your awsaccess object"
					else
						# open the connection to AWS
						@@connections[reg] = {} if (!@@connections[reg])
						@@connections[reg][name] = Fog::Compute.new(:provider => 'aws', :aws_access_key_id => @@credentials[name][:aws_access_key_id], :aws_secret_access_key => @@credentials[name][:aws_secret_access_key], :region => reg)
						raise "Sorry, I could not create a connection to '#{region}' with awsaccess object '#{name}'" if (!@@connections[reg][name])
						return @@connections[reg][name]
					end
				else
					raise "Sorry, awsaccess object '#{name}' does not exist!"
				end
			end
		end
	end
end
		
