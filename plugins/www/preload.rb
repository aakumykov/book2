# coding: utf-8

class WwwPreload_Plugin < PluginSkel

	def work(arg)
		Msg.red "#{self.class}.#{__method__}(#{arg.keys.join(',')})" 
		
		Book.plugin(
			:name => 'www/filter_uri',
			:data => arg[:data],
			:uuid => arg[:uuid],
		)
		
		#return arg[:data]
	end
end
