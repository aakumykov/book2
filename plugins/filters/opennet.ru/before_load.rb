
class Plugin_before_load < PluginSkel
	def work(arg)
		data = arg[:data]
		uuid = arg[:uuid]
		
		puts "#{self.class}.#{__method__}(), #{uuid}".red
		
		new_data = data
	end
end
