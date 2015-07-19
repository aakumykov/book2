# coding: utf-8
system 'clear'

require 'net/http'
require 'awesome_print'

def detectCharset(body, headers)

    charset_h = ''
    if (not headers.nil?) then
        headers.each_pair { |key,value|
            if key.downcase.strip == 'content-type' then
                res = value.scan(/charset\s*=\s*([^=]+)/i)
                charset_h = res[0] if not res.empty?
            end
        }
    end
    
    charset_p = ''
    if res = body.scan(/<\s*meta[^>]+http-equiv[^>]+content-type[^>]+content[^>]+charset\s*=\s*([^=]+)/i) then
        charset_p = res[0]
    end
end

def fetch(uri_str, limit = 10)
  # You should choose a better exception.
  raise ArgumentError, 'too many HTTP redirects' if limit == 0

  response = Net::HTTP.get_response(URI(uri_str))

  case response
  when Net::HTTPSuccess then
    response
  when Net::HTTPRedirection then
    location = response['location']
    warn "redirected to #{location}"
    fetch(location, limit - 1)
  else
    response.value
  end
end

puts fetch('http://www.ruby-lang.org')
