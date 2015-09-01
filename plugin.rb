# coding: utf-8
system 'clear'

class Master
	@@a = nil
	@@b = nil
	@@options = {
		:name => "*CLASS* #{self} *CLASS*",
		:depth => 5,
		:plugin_log => []
	}

	def initialize
		@@a = 10
		@@b = 20
	end

	def self.plugin(name,data)
		plugin = Object.const_get(name).new
		puts "@: #{plugin.to_s}"
		
		@@options[:plugin_log] << name
		
		plugin.set_uuid 'some UUID'
		
		plugin.work(data)
	end
end

class PluginSkel
	attr_reader :uuid

	def initialize
		puts "initialize #{self.class}"
	end
	
	def set_uuid(value)
		@uuid = value
	end
	
	def work(data=nil)
		puts "#{self.class}.#{__method__}(), #{self}, #{caller}"
	end
end

class Plugin1 < PluginSkel
	def work(data)
		super
		new_data = "#{data} / #{self.class}.#{__method__}"
		new_data = Master.plugin('Plugin2',new_data)
	end
end

class Plugin2 < PluginSkel
	def work(data)
		super
		new_data = "#{data} / #{self.class}.#{__method__}"
	end
end

class Html < PluginSkel
	def work(data)
		super
		new_data = Master.plugin('Clear',data)
		new_data = Master.plugin('Txt',new_data)
	end
end

class Txt < PluginSkel
	def work(data)
		super
		new_data = "#{data} / #{self.class}.#{__method__}"
		Master.plugin('Clear',new_data)
	end
end

class Clear < PluginSkel
	def work(data)
		super
		new_data = "#{data} / #{self.class}.#{__method__}"
	end
end


m = Master.new
puts Master.plugin('Plugin1','initial data')
#puts Master.plugin('Html','initial data')
#puts "call log: #{Master.get_option(:plugin_log).join(',')}"