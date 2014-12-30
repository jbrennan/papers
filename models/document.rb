require 'data_mapper'
require './models/user.rb'
require './models/author.rb'


class Document
	include DataMapper::Resource
	
	property :id,	Serial
	property :title,	String, :length => 250
	property :file_path,	String, :length => 250
	
	property :created_at,	DateTime

	
	belongs_to :user
	has n, :authors, :through => Resource
	
end