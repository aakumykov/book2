
class PluginSkel

end

class Html < PluginSkel
	def work(arg)
		uuid = arg[:uuid]
		data = arg[:data]
		
		data = Book.plugin(
			:name => 'Clear',
			:data => data,
			:uuid => uuid,
		)
		
		data = Book.plugin(
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
