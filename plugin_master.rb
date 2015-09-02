# coding: utf-8

class PluginMaster
	@@log = {}
	
	# Сильно большой лог - ошибка (аналог SYN-flood)

	def self.call (arg)
		uuid = arg[:uuid]
		name = arg[:name]
		data = arg[:data]
		
		puts "#{self}.#{__method__}('#{name}')"
		
		raise new Exception "invalid UUID" if not arg[:uuid].match(/^[abcdef0-9]{8}-[abcdef0-9]{4}-[abcdef0-9]{4}-[abcdef0-9]{4}-[abcdef0-9]{12}$/)
		
		@@log[uuid] = [] if not @@log.has_key?(uuid)
		@@log[uuid] << name
		
		begin
			plugin = Object.const_get(name).new
		rescue
			puts "There is no plugin '#{name}'".red
			return data
		end
		
		#plugin.work (arg[:data])
	end
end

class PluginSkel
end

class Html < PluginSkel
	def work(data)
		new_data = "#{data} / #{self.class}.#{__method__}"
		Master.plugin('Plugin2',new_data)
	end
end

class Text < PluginSkel
	def work(data)
		"#{data} / #{self.class}.#{__method__}"
	end
end

class Clear < PluginSkel
	def work(data)
		"#{data} / #{self.class}.#{__method__}"
	end
end

class URINormalize < PluginSkel
	def work(data)
		"*NORMALIZED* #{data} *NORMALIZED*"
	end
end


#~ PluginMaster.call(
	#~ :uuid => '5df05ea8-dd60-463d-8481-51bd3f7e839d',
	#~ :name => 'Clear',
	#~ :data => nil
#~ )