# -*- coding: utf-8 -*- 

require 'rubygems'
require "bundler/setup"
require 'fileutils'

require 'sinatra'
require "sinatra/reloader" if development?

require 'haml'
require 'json'
require 'data_mapper'
require 'email_veracity'
require 'redcarpet'
require 'builder'

require 'date'
require 'time'

require './defaults.rb'

# require './util/pbkdf2.rb'
require 'pbkdf2'
require './util/config.rb'
require './util/constants.rb'

require './models/user.rb'
require './models/document.rb'
require './models/author.rb'


enable :logging
use Rack::CommonLogger

#erb stuff for models?
DataMapper.finalize
DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/db_#{SiteName.downcase.gsub(' ', '_')}.sqlite3")
DataMapper.auto_upgrade!


configure :production do
	enable :dump_errors
	enable :logging
	enable :raise_errors
end


helpers do
	
	# mostly atom feed helpers
	def base_url
		url = "http://#{request.host}"
		request.port == 80 ? url : url + ":#{request.port}"
	end
	
	def base_url_for_document(document)
		path = uploads_directory.gsub("public", "")
		base_url + path
	end
	
	def url_for_document_page(document)
		base_url + "/documents/" + document.filename
	end
	
	def url_for_document(document)
		base_url_for_document(document) + document.filename
	end
	
	def pretty_date(date)
		date.strftime("%A, %B %e %Y")
	end
	
	# directory helpers
	def user_directory
		"public/user/"
	end
	
	def user_files_directory
		user_directory + "files/"
	end
	
	def uploads_directory
		user_files_directory
	end
	
	def ensure_uploads_directory_exists
		ensure_directory_exists(uploads_directory)
	end
	
	def ensure_directory_exists(directory)
		if File.directory?(directory)
			return
		end
		
		FileUtils.mkpath(directory)
	end
	
	
	def sanitize_string(string)
		string.downcase.gsub(/[^a-zA-Z\d]/, "_")
	end
	
	
	def path_by_saving_file_with_filename(file, filename)
		ensure_uploads_directory_exists
		
		path = uploads_directory + filename
		
		File.open(path, "w") do |f|
			f.write(file[:tempfile].read)
		end
		
		return path
	end
	
	def editable(property_name)
		"class = 'editable' onfocus = 'focussedEditable(event);' onblur = 'blurredEditable(event);' onkeydown = 'keyDownOnEditable(event);' contenteditable data-property = '#{property_name}'"
	end
	
	
	def secondary_text
		"class = 'secondary-text'"
	end
	
end


before do
	$user = nil
	authorize_user(request.cookies['auth'])
	puts $user.inspect
end


before "/dashboard/*" do
	redirect "/login" if !$user
end



before "/api/*" do
	content_type 'application/json'
	
	if request.request_method.upcase == 'POST' && !request.form_data?
		@data = JSON.parse(request.body.read)
	end
	
end

get '/' do
	@documents = []
	if $user
		@documents = Document.all(:user => $user, :order => [:created_at.desc])
	end
	
	erb :index
end


get '/documents/:document_id' do
	@document = Document.first(:filename => params[:document_id])
	erb :document_page
end



get '/login' do
	@logging_in = true
	haml :dashboard_login, :layout => :dashboard_layout
end


get '/logout' do
	request.cookies['auth'] = "" # this does nothing... look at request.set_cookie()
	redirect '/'
end


get '/dashboard' do
	redirect "/login" if !$user
	redirect "/"
end


###
# Debug pages
###

get '/debug' do
	# list all debug pages
	@models = Array.new
	DataMapper::Model.descendants.each do |model|
		@models << model
	end
	
	@models.each do |m|
		m.properties.each do |p|
			puts p.name.to_s
		end
	end
	
	haml :debug
end

get '/debug/:class' do
	@class_name = params[:class]
	class_instance = Kernel.const_get(@class_name)
	return "No matching class" if nil == class_instance
	
	@properties = Array.new
	class_instance.properties.each do |property|
		@properties << property
	end
	
	@instances = Array.new
	collection = class_instance.all
	
	return "No rows for class #{@class_name}" if collection == nil or collection.empty?
	
	collection.each do |row|
		@instances << row
	end
	haml :debug_instances
end

get '/debug/:class/:id' do
	@class_name = params[:class]
	class_instance = Kernel.const_get(@class_name)
	return "No matching class" if nil == class_instance
	
	@object = class_instance.first(:id => params[:id])
	haml :debug_object
end



#########################
# API
#########################

post '/api/user/login' do
	
	return api_error(ErrorMissingParameter) if !check_json_parameters(@data, "username", "password")
	
	# if (!check_parameters("username", "password"))
	# 	return {
	# 		:status => APIStatusError,
	# 		:error => ErrorMissingParameter
	# 	}.to_json
	# end


	auth_token,api_secret = check_user_credentials(@data["username"], @data["password"])

	if auth_token
		return {
			:status => APIStatusOK,
			:auth_token => auth_token,
			:api_secret => api_secret
		}.to_json
	else
		return {
			:status => APIStatusError,
			:error => ErrorBadCredentials
		}.to_json
	end

end


# This logs the user out of all sessions everywhere
# Meaning any apps will have to request a new token
post '/api/user/logout_sessions' do
	
	
	if $user and check_api_secret
		update_auth_token
		return {
			:status => APIStatusOK
		}.to_json
	else
		return {
			:status => APIStatusError,
			:error => ErrorBadAPICredentials
		}.to_json
	end
end


post '/api/user/create' do
	content_type 'application/json'
	
	allows_new_signups = Defaults[:account_allows_signups]
	if allows_new_signups == nil
		puts "nil allows signups"
		allows_new_signups = true # allows the first signup, but then will default to false.
	end
	
	if allows_new_signups == false
		puts "signups not allowed?"
		return api_error "Signups are not allowed at this time."
	end
	
	if (!check_json_parameters(@data, "username", "password"))
		return {
			:status => APIStatusError,
			:error => ErrorMissingParameter
		}.to_json
	end
	
	
	if (!email_address? @data["username"])
		return {
			:status => APIStatusError,
			:error => ErrorMessageNotEmailAddress
		}.to_json
	end
	
	
	if @data["password"].length < MinPasswordLength
		return {
			:status => APIStatusError,
			:error => ErrorPasswordTooShort
		}.to_json
	end
	
	auth_token, error_message = create_user(@data["username"], @data["password"])
	if auth_token
		return {
			:status => APIStatusOK,
			:auth_token => auth_token
		}.to_json
	else
		return {
			:status => APIStatusError,
			:error => error_message
		}.to_json
	end
	
end


get '/api/user/exists' do
	
	return {
		:exists => true
	}.to_json if user_already_exists(params[:username])

	return {
		:exists => false
	}.to_json
end


post '/api/v1/document/upload' do
	params.each_key { |key|
		file = params[key]
		if file[:type] != "application/pdf"
			status 415
			return api_error "File must be a pdf, was #{file[:type]} instead"
		end
		
		
		filename = SecureRandom.uuid  + ".pdf"# I'd love for this to be a SHA of the file instead...
		
		path_by_saving_file_with_filename file, filename
		
		author = Author.create # I'd love to be able to parse this out of the pdf...
		author.name = "unknown author"
		
		document = Document.create
		document.original_filename = key
		document.filename = filename
		document.title = key
		document.authors << author
		
		document.user = $user
		
		document.save
		$user.save
		author.save

	}
	
	return api_OK
end


post "/api/v1/updatekey" do
	return api_error ErrorWrongSecret if !check_api_secret @data
	return api_error "Hey, you don't own this document!" if !user_owns_document @data
	
	# I know ruby can do this dynamically but it's after midnight...so I'll hardcode it for now...
	key = @data["property"]
	
	if key == "document.title"
		document = Document.first(:id => @data["documentID"])
		document.title = @data["value"]
		document.save
	elsif key == "document.author"
		document = Document.first(:id => @data["documentID"])
		document.authors.first.name = @data["value"]
		document.authors.first.save
	elsif key == "document.notes"
		document = Document.first(:id => @data["documentID"])
		document.notes = @data["value"]
		document.save
	else
		return api_error "Trying to set unrecognized key...#{key}"
	end
	
	return api_OK
end


### Utilities

# Returns two values:
# => auth token if the registration succeeds, otherwise nil
# => error message if the registration failed
def create_user(email, password)
	if user_already_exists(email)
		return nil, ErrorEmailAlreadyInUse
	end

	auth_token = get_random()
	salt = get_random()

	# create the user, and save
	@new_user = User.create(
		:email => email,
		:salt => salt,
		:password => hash_password(password, salt),
		:user_created_at => Time.now,
		:auth_token => auth_token,
		:api_secret => get_random,
		:user_flags => "" 
	)
	return auth_token, nil
end


# User authentication
# This method tries to authenticate the user, and populates the $user gloabl on success
# Otherwise, $user is set to nil so it can be checked for later
# Note: this is called before every route
def authorize_user(auth)
	return if !auth

	# try to look up the user according to their auth_token
	user = User.first(:auth_token => auth)
	$user = user if user != nil
end


def get_random
	random = ""
	File.open("/dev/urandom").read(20).each_byte { |x|
		random << sprintf("%02x", x)
	}
	random
end


def user_already_exists(email)
	User.first(:email => email) != nil
end


def hash_password(password, salt)
	p = PBKDF2.new do |p|
		p.iterations = 5000
		p.password = password
		p.salt = salt
		p.key_length = 160/8
	end
	p.hex_string
end


# Check to make sure the supplied list exists
def check_parameters *required
	required.each { |p|
		params[p].strip! if params[p] and params[p].is_a? String
		if !params[p] or (p.is_a? String and params[p].length == 0)
			return false
		end
	}
	true
end


def check_json_parameters hash, *required
	required.each do |p|
		hash[p].strip! if hash[p] and hash[p].is_a? String
		if !hash[p]
			return false
		end
	end
	true
end


# Checks if the credentials identify a user.
# If so, returns the auth and secret.
# Otherwise, returns nil
def check_user_credentials (email, password)
	user = get_user_by_email(email)
	return nil if !user
	hashed = hash_password(password, user[:salt])
	(user[:password] == hashed) ? [user[:auth_token], user[:api_secret]] : nil
end


# Checks to make sure a request is coming in with the proper API secret for this user
def check_api_secret hash
	return false if !$user
	return (hash["apisecret"] and (hash["apisecret"] == $user[:api_secret]))
	return (params["apisecret"] and (params["apisecret"] == $user[:api_secret]))
end


def user_owns_document data
	return false if !$user
	
	Document.first(:id => data["documentID"]).user == $user
end


# Checks to see if the provided email address is valid
def email_address? email
	address = EmailVeracity::Address.new(email)
	return address.valid?
end



# Updates the auth token for the given user.
# This has essentially logs the user out of all their sessions everywhere
def update_auth_token(user)
	new_auth_token = get_random
	user[:auth_token] = new_auth_token
	user.save
	return new_auth_token
end


def get_user_by_email(email)
	User.first(:email => email)
end


def api_error(error_message)
	return {
		:status => APIStatusError,
		:error => error_message
	}.to_json
end


def api_OK
	return {
		:status => APIStatusOK
	}.to_json
end

