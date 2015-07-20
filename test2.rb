# coding: utf-8
system 'clear'; require 'net/http'; require 'awesome_print'

def detectCharset(page,headers={})
	
	page_charset = nil
	header_charset = nil

	pattern = Regexp.new(/charset\s*=\s*['"]?(?<charset>[^'"]+)['"]?/i)

	page.encode!('UTF-8',{:replace => '_',:invalid => :replace,:undef => :replace})
	res = page.match(pattern)
	page_charset = res[:charset] if not res.nil?

	headers.each_pair { |k,v|
		if 'content-type'==k.downcase.strip then
			res = v.first.downcase.strip.match(pattern)
			header_charset = res[:charset] if not res.nil?
		end
	}

	#return page_charset if header_charset.nil?
	#return header_charset
	return {
		:header_charset => header_charset,
		:page_charset => page_charset,
	}
end

puts "Usage: [ruby] #{__FILE__} <uri>" and exit(1) if 1 != ARGV.size

uri = URI(ARGV[0])

#resp = Net::HTTP.get_response(uri)
req = Net::HTTP::Get.new(uri)
req['User-Agent'] = 'Googlebot/2.1 (+http://www.googlebot.com/bot.html)'
resp = Net::HTTP.Start { |http|
	http.request(req)
}

headers = resp.to_hash
ap headers

puts detectCharset(resp.body,headers)