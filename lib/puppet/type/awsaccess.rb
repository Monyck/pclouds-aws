require 'rubygems'
require 'facter'
require 'fog'
require 'yaml'

Puppet::Type.newtype(:awsaccess) do
	@doc = "The awsaccess resource allows us to configure different access credemtials and regions of operation through puppet"

	# Allow to be ensurable
	ensurable

	newparam(:name) do
		desc "A name for the access resource, must be unique"
		isnamevar
		defaultto "awsconfig"
	end

	newproperty(:aws_access_key_id) do
		desc "The AWS Access Key"
		isrequired
		validate do |value|
			unless (value.length == 20 && value =~ /^[A-Za-z0-9]+/) then
				fail("A valid aws_access_key_id is a 20 character alphanumeric!")
			end
		end
	end

	newproperty(:aws_secret_access_key) do
		desc "The AWS Secret Access Key"
		isrequired
		validate do |value|
			unless (value.length == 40 && value =~ /^[A-Za-z0-9\/+]+/) then
				fail("A valid aws_secret_access_key is a 40 character alphanumeric (plus / and +)!")
			end
		end
	end

	newproperty(:regions, :array_matching => :all) do
		desc "An array regions which we will manage from this server, default all of them."
		newvalues(/^eu-west-\d$/, /^us-east-\d$/, /^us-west-\d$/, /^ap-southeast-\d$/, /^ap-northeast-\d$/, /^sa-east-\d$/)
	end

end
