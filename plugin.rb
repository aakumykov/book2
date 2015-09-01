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
		#puts "#{self}.#{self.class}.#{__method__}"
		@@a = 10
		@@b = 20
	end

	def self.plugin(name,data)
		p = Object.const_get(name).new
		@@options[:plugin_log] << name
		p.work(data)
	end

	def plugin(name,data)
		self.class.plugin(name,data)
	end

	def self.get_option(key)
		@@options[key]
	end

	def set_option(key,value)
		@@options[key] = value
	end
end

class PluginSkel
	def initialize
		#puts "#{self}.#{self.class}.#{__method__}"
	end
end

class Plugin1 < PluginSkel
	def work(data)
		new_data = "#{data} -*- #{self.class}.#{__method__} -*- #{Master.get_option(:name)}"
		Master.plugin('Plugin2',new_data)
	end
end

class Plugin2 < PluginSkel
	def work(data)
		"#{data} -*- #{self.class}.#{__method__} -*- #{Master.get_option(:depth)}"
	end
end

m = Master.new
puts Master.plugin('Plugin1','initial data')
#puts Master.plugin('Plugin2','initial data')
#puts m.plugin('Plugin1','qwerty')
#puts m.plugin('Plugin2','йцукен')
puts Master.get_option(:plugin_log).join(',')
