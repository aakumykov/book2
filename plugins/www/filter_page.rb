# coding: utf-8

class WwwFilter_Page_Plugin < PluginSkel

	def work(arg)
		#Msg.red("#{self.class}.#{__method__}(#{arg[:uri]}, #{arg[:data].size>80 ? arg[:data].size : arg[:data]})")
		Msg.red "#{self.class}.#{__method__}(#{arg.keys.join(',')})"
		
		#filter = getFilter...
		
		return arg[:data]
	end
end
