# coding: utf-8

class WwwPostload_Plugin < PluginSkel

	def work(arg)
		Msg.red "#{self.class}.#{__method__}(#{arg.keys.join(',')})"
		
		data = arg[:data]
		ref_uri = arg[:uri]
		
		new_uri = data.match(/^\/openforum\/vsluhforumID3\/\d+\.html#1/)[0]
		new_uri = URI(ref_uri).host + new_uri
		
		new_page = Book.plugin(
			:name => 'www/load',
			:data => new_uri,
			:uri => ,
			:uuid => arg[:uuid],
		)
		
		# опасно, возможность зацикливания!
		new_page = Book.plugin(
			:name => 'www/load',
			:data => new_page,
			:ref_uri => new_uri,
			:uuid => arg[:uuid],
		)
	end
end
