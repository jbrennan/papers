require 'data_mapper'
require './models/user.rb'
require './models/author.rb'


class Document
	include DataMapper::Resource
	
	property :id,	Serial
	property :title,	String, :length => 250
	property :filename,	String, :length => 250
	property :original_filename, String, :length => 250
	property :notes, Text
	
	property :created_at,	DateTime

	
	has n, :users, :through => Resource
	has n, :authors, :through => Resource
	
end