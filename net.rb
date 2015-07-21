#coding: utf-8
system 'clear'
require 'net/http'
require 'awesome_print'

#uri = URI('http://opennet.ru')
#uri = URI('http://kondor.webhost.ru/_SERVER.php?a=AA&b=BB')


def fetch(uri,limit=10)

	raise ArgumentError, 'too many HTTP redirects' if limit == 0

	begin
		uri = URI(uri)
	rescue
		uri = URI( URI.escape(uri) )
	end

	Net::HTTP.start(uri.host, uri.port) do |http|
  		request = Net::HTTP::Get.new uri.request_uri
  		request['User-Agent'] = 'Ruby client <aakumykov@yandex.ru>'
  		
  		response = http.request request

		case response
		when Net::HTTPRedirection then
			location = response['location']
			warn "redirected to #{location}"
			fetch(location, limit - 1)
		else
			response.value
		end

		return {
			:headers => response.to_hash,
			:page => response.body,
		}
	end
end

( puts "Usage: ruby #{__FILE__} <URI>"; exit(1) ) if 1 != ARGV.size

uri = ARGV[0]

ap fetch(uri)[:headers]