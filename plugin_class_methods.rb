# coding: utf-8
system 'clear'

class Matka
	@@a = 0
	@@b = 0
	
	def self.increase
		puts "#{self}.#{__method__}()"
		@@a+=1
		@@b+=1

		self.info
	end


	def self.info
		puts "#{self}.#{__method__}()"
		puts "@@a: #{@@a}"
		puts "@@b: #{@@b}"
	end

	def info
		Matka.info
	end


	def initialize
		puts "#{self.class}.#{__method__}()"

		@@a = 10
		@@b = 20

		info
	end
	

	def self.plugin(name)
		p = Object.const_get(name).new
		#p.work
	end
end


class PluginBase
	def initialize
		puts "#{self.class}.#{__method__}()"
	end
end

class Plugin1 < PluginBase
	def initialize
		super
		Matka.plugin('Plugin2')
	end
end

class Plugin2 < PluginBase
end



Matka.plugin('Plugin1')




