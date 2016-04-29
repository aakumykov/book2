#!/usr/bin/env ruby

# coding: utf-8

require 'colorize'
require 'uri'


class String
	def urlencoded?
		return true if self.match(/%[0-9ABCDEF]{2}/i)
		return false
	end

	def latin1?
		return true if self.match(/^[ -~]*$/)
		return false
	end
end

module URI
	def self.smart_decode(str)
		str.urlencoded? ? URI.decode(str) : str
	end

	def self.smart_encode(str)
		str.latin1? ? str : URI.encode(str)
	end
end

class Msg
	@@alerts_count = 0
	@@errors_count = 0

	def self.alerts_count
		@@alerts_count
	end
	def self.errors_count
		@@errors_count
	end

	def self.debug(arg,options={})
		print arg.to_s.white
		print 10.chr if options.fetch(:new_line,true)
	end

	def self.info(arg)
		puts arg.to_s + 10.chr
	end

	def self.error(arg)
		@@errors_count += 1
		arg = arg.to_s
		puts ("ОШИБКА: " + arg).red + 10.chr
		#File.open(@@error_log,'w') if not File.exists?(@@error_log)
		#File.open(@@error_log,'a') { |file| file.write(arg+10.chr) }
	end
	
	def self.alert(arg)
		@@alerts_count += 1
		arg = arg.to_s
		puts ("###: " + arg).yellow + 10.chr
		#File.open(@@alert_log,'w') if not File.exists?(@alert_log)
		#File.open(@@alert_log,'a') { |file| file.write(arg+10.chr) }
	end
	
	def self.blue(arg)
		puts arg.to_s.blue + 10.chr
	end
	
	def self.green(arg)
		puts arg.to_s.green + 10.chr
	end
	
	def self.cyan(arg)
		puts arg.to_s.cyan + 10.chr
	end
	
	def self.red(arg)
		puts arg.to_s.red + 10.chr
	end
	
	def self.ahtung(arg)
		puts arg.to_s.black.on_yellow + 10.chr
	end
end

class BookConfig
	def self.with_discussion?
		true
	end

	def self.with_linux?
		true
	end
end

class MatchException < Exception
end

class DefaultSite_Config
	
	def rules_for_uri(uri,rules_type)
		sorted_rules = @link_rules.sort_by{ |k,v| k.length }
		
		sorted_rules.reverse_each { |pattern,rule_set|
			if uri.match(pattern) then
				return rule_set.fetch(rules_type,{}).sort_by { |k,v| v.length }
			end
		}
		
		return {}
	end

	def acceptLink?(uri)
		#Msg.debug("#{__method__}(#{lnk})")

		uri = URI.smart_decode(uri)
		#Msg.debug(uri)
		
		accept_rules = rules_for_uri(uri,:accept)
		decline_rules = rules_for_uri(uri,:decline)

		positive = check_rules(uri,accept_rules)
		negative = check_rules(uri,decline_rules)

		Msg.blue("positive: #{positive}, negative: #{negative}, ИТОГ: #{positive && !negative}")

		return positive && !negative
	end

	def check_rules(subject,rule_set)
		#Msg.debug("Checking rules for '#{link}'")

		rule_set.each { |type,value|
			case type
			when :regex
				if check_regex(subject,value)
					#Msg.debug("совпало: #{value}")
					return true
				end
			when :name
				return true if check_rule(subject,rules_subset(value))
			when :cond_regex
				if value[:condition] then
					return true if check_regex(subject,value[:regex])
				end
			when :cond_name
				if value[:condition]
					return true if check_rule(subject,rules_subset(value[:name]))
				end
			end
		}

		return false
	end

	def check_regex(string,regexp)
		Msg.debug("#{__method__}('#{string}', '#{regexp}')")
		string.match(regexp)
	end

	def rules_subset(name)
		Msg.debug("Вложенный набор правил '#{name}'")

		@@link_rules.each { |k,v| return v[:accept] if v[:name]==name }

		Msg.alert("Набор правил '#{name}' не существует")
		return []
	end

	def repair_uri(uri)
		#Msg.blue("input uri: #{uri}")
		#Msg.blue("urlencoded?: #{uri.urlencoded?}")
		#Msg.blue("latin1?: #{uri.latin1?}")
		
		uri = URI( URI.smart_encode(uri.strip) )

		if uri.to_s.match(/^\//)
			#Msg.blue("URIed uri: #{uri}")
			uri.scheme = @config[:scheme] if uri.scheme.to_s.empty?
			uri.host = @config[:host] if uri.host.to_s.empty?
			uri.path = @config[:path] if uri.path.to_s.empty?
			uri.query = @config[:query] if uri.query.to_s.empty?
		end
		
		#Msg.blue("path: #{uri.path}")
		#Msg.blue("восстановленный uri: #{uri.to_s}")
		
		return uri.to_s
	end

	def humanize_link(str)
		URI.decode( self.wikipedia_decode(str) )
	end

	def wikipedia_decode(str)
		if str.match(/wikipedia\.org/)
			str.gsub(/\.(?<hex_code>[0-9A-F]{2})/,'%\k<hex_code>')
		else
			str
		end
	end
end

class Wikipedia_Config < DefaultSite_Config
	@@config = {
		scheme: 'https',
		host: 'ru.wikipedia.org',
	}

	@@link_rules = {
		'.*' => {
		 	name: :all_pages,
		 	accept: {
				regex: '^https:\/\/ru\.wikipedia\.org\/wiki\/[^#<>\[\]|{}�: ]+$',
				#regex: '^https:\/\/ru\.wikipedia\.org\/wiki\/[^\/]+$',
				#name: :service,
				#cond_regex: { regex: 'Linux', condition:BookConfig.with_linux? },
				#cond_name: { name: :discussion, condition:BookConfig.with_discussion? },
			},
			decline: {
				regex: 'ru\.wikipedia\.org\/wiki\/Заглавная_страница$',
				#regex: '.*',
			},
		},
		'/Обсуждение:[^:]+$' => {
			name: :discussion,
			accept: {
				regex: '.*'
			}
		}
	}

	def initialize(start_lnk)
		@config = @@config
		@link_rules = @@link_rules
		
		uri = URI(URI.encode(start_lnk))
		  @config[:path] = uri.path
		  @config[:query] = uri.query

		#Msg.debug(@config)
	end
end


if 2==ARGV.count then
	input_link = ARGV[0]
	input_file = ARGV[1]
else
	puts "Usage: #{__FILE__} <input_link> <input_file>"
	exit false
end

site_config = Wikipedia_Config.new(input_link)
#site_config.repair_uri(input_link); exit

data = File.read(input_file)
hrefs = data.scan(/href\s*=\s*['"][^'"]+['"]/)
hrefs.each { |uri|
	uri = uri.match(/href\s*=\s*['"](?<the_uri>[^'"]+)['"]/)[:the_uri].strip
	
	uri = site_config.repair_uri(uri)
	Msg.red("Проверяю ссылку: #{uri}")

	if site_config.acceptLink?(uri)
		Msg.green( site_config.humanize_link(uri))
	else
		#Msg.red(uri)
	end
}
