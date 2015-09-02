# coding: utf-8

class PluginMaster
	@@log = {}
	
	# Сильно большой лог - ошибка (аналог SYN-flood)

	def self.call (arg)
		uuid = arg[:uuid]
		name = arg[:name]
		data = arg[:data]
		
		puts "#{self}.#{__method__}('#{name}')"
		
		raise "invalid UUID (#{uuid})" if not arg[:uuid].match(/^[abcdef0-9]{8}-[abcdef0-9]{4}-[abcdef0-9]{4}-[abcdef0-9]{4}-[abcdef0-9]{12}$/)
		
		if not @@log.has_key?(uuid) then
			puts "новый uuid: #{uuid}"
			@@log[uuid] = []
		else
			puts "повторный uuid: #{uuid}"
		end
		
		@@log[uuid] << name
		
		begin
			plugin = Object.const_get(name).new
		rescue
			puts "There is no plugin '#{name}'".red
			return data
		end
		
		plugin.work(
			:uuid => arg[:uuid],
			:data => arg[:data],
		)
	end
end

class PluginSkel

end

class Html < PluginSkel
	def work(arg)
		uuid = arg[:uuid]
		data = arg[:data]
		
		data = PluginMaster.call(
			:name => 'Clear',
			:data => data,
			:uuid => uuid,
		)
		
		data = PluginMaster.call(
			:name => 'StripTags',
			:data => data,
			:uuid => uuid
		)
	end
end

class StripTags < PluginSkel
	def work(arg)
		uuid = arg[:uuid]
		data = arg[:data]
		
		data = data.gsub(/<\/?[^<>]+>/,'')
	end
end

class Text < PluginSkel
	def work(arg)
		uuid = arg[:uuid]
		data = arg[:data]
	end
end

class Clear < PluginSkel
	def work(arg)
		uuid = arg[:uuid]
		data = arg[:data]
	end
end

class URINormalize < PluginSkel
	def work(arg)
		uuid = arg[:uuid]
		data = arg[:data]
		"*NORMALIZED* #{data} *NORMALIZED*"
	end
end
