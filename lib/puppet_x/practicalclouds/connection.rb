require 'fog'

# This helper class manages and shares connections to AWS so that
# provider functions don't all have to open their own connections

class Puppet::Puppet_X::Practicalclouds::Awsconnect

	@@yamlfile="#{Puppet[:confdir]}/aws.yaml"
	@@credentials = {}
	@@connections = {}

	def self.connect(name,reg)
		# return an existing matching connection...
		if (@@connections[reg])
			if (@@connections[reg][name]) 
				return @@connections[reg][name]
			end
		end

		if (@@credentials == {})
			@@credentials = YAML::load(File.open(@@yamlfile))
		end

		if (@@credentials[name])
			if (@@credentials[name][:regions] && !@@credentials[name][:regions].member?(reg))
				raise "Credential '#{name}' is not allowed in region '#{reg}'"
			elsif (!@@credentials[name][:aws_access_key_id] || !@@credentials[name][:aws_secret_access_key])
				raise "You need to have both an aws_access_key_id and aws_secret_access_key in your access object"
			else
				# open the connection to AWS
				@@connections[reg][name] = Fog::Compute.new(:provider => 'aws', :aws_access_key_id => @@credentials[name][:aws_access_key_id], :aws_secret_access_key => @@credentials[name][:aws_secret_access_key], :region => reg)
				raise "Sorry, I could not create a connection to '#{region}' with access object '#{name}'" if (!@@connections[reg][name])
				return @@connections[reg][name]
			end
		else
			raise "Sorry, access object '#{name}' does not exist!"
		end
	end
end
		
