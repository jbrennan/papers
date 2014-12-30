require 'data_mapper'
require './models/document.rb'


class Author
	include DataMapper::Resource
	
	property :id,	Serial
	property :name,	String
	
	
	property :created_at,	DateTime

	has n, :documents, :through => Resource
	
end