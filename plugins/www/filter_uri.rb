# coding: utf-8

class WwwFilter_Uri_Plugin < PluginSkel

	def getURIFilter(uri)
		filter_list = []
		Dir.entries('filters/').each { |e|
			next if not 'uri_rules.rb' == e
			rules = nil
			require 
		}
	end

	def work(arg)
		#Msg.red("#{self.class}.#{__method__}(#{arg[:uri]}, #{arg[:data].size>80 ? arg[:data].size : arg[:data]})")
		Msg.red "#{self.class}.#{__method__}(#{arg.keys.join(',')})"
		
		uri = arg[:data]
		
		filter = getURIFilter(uri)
		
		return arg[:data]
	end
end
