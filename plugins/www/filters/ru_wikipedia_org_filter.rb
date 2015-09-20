# coding: utf-8

class RuWikipediaOrgFilter < FilterSkel

	@@rules = {
		'^https:\/\/ru\.wikipedia\.org\/wiki\/[\w%]+' => 'article',
		'^https:\/\/ru\.wikipedia\.org\/w\/index\.php\?title=[^&?=]+&printable=yes' => 'article_printable',
	}

	def article(arg)
		Msg.blue "#{self.class}.#{__method__}(#{arg})"
		
		if (article_name = arg[:uri].match(/[^\/]+$/)[0]).strip.empty? then
			Book.plugin(
				name: 'www/load',
				data: arg[:uri],
				uuid: SecureRandom.uuid,
			)
		else
			new_uri = "https://ru.wikipedia.org/w/index.php?title=#{article_name}&printable=yes"
			self.process(uri: new_uri)
			# А надо бы: Book.filter(uri: new_uri)
		end
	end


	def article_printable(arg)
		Msg.blue "#{self.class}.#{__method__}(#{arg})"
		Book.plugin(
			name: 'www/load',
			data: arg[:uri],
			uuid: SecureRandom.uuid,
		)
	end
end
