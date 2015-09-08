# coding: utf-8

class WwwPostload_Plugin < PluginSkel

	def work(arg)
		#Msg.red("#{self.class}.#{__method__}(#{arg[:uri]}, #{arg[:data].size>80 ? arg[:data].size : arg[:data]})")
		Msg.red "#{self.class}.#{__method__}(#{arg.keys.join(',')})"
		
		Book.plugin(
			:name => 'www/filter_page',
			:data => arg[:data],
			:uuid => arg[:uuid],
		)
		
		return arg[:data]
	end
end
