# coding: utf-8

class WwwPreload_Plugin < PluginSkel

	def work(arg)
		#Msg.cyan
		return arg[:data]
	end
end
