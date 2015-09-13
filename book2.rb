#!/usr/bin/env ruby
# coding: utf-8

system 'clear'

require 'rubygems'
require 'zip'
require 'find'
require 'open3'
require 'sqlite3'
require 'securerandom'
require 'digest/md5'
require 'tmpdir'
require 'tempfile'
require 'fileutils'
require 'nokogiri'
require 'net/http'
require 'colorize'	# must be after 'curl' for right colors
require 'awesome_print'
require 'uri'

class Msg
	@@alerts_count = 0
	@@errors_count = 0

	def self.alerts_count
					@@alerts_count
	end
	def self.errors_count
					@@errors_count
	end


	def self.debug(arg)
		#puts arg.to_s.white + 10.chr
	end

	def self.info(arg)
		puts arg.to_s + 10.chr
	end

	def self.error(arg)
		@@errors_count += 1
		arg = arg.to_s
		puts ("ОШИБКА: " + arg).red + 10.chr
		#File.open(@@error_log,'w') if not File.exists?(@@error_log)
		#File.open(@@error_log,'a') { |file| file.write(arg+10.chr) }
	end
	
	def self.alert(arg)
		@@alerts_count += 1
		arg = arg.to_s
		puts ("###: " + arg).yellow + 10.chr
		#File.open(@@alert_log,'w') if not File.exists?(@alert_log)
		#File.open(@@alert_log,'a') { |file| file.write(arg+10.chr) }
	end
	
	def self.blue(arg)
		puts arg.to_s.blue + 10.chr
	end
	
	def self.green(arg)
		puts arg.to_s.green + 10.chr
	end
	
	def self.cyan(arg)
		puts arg.to_s.cyan + 10.chr
	end
	
	def self.red(arg)
		puts arg.to_s.red + 10.chr
	end
	
	def self.ahtung(arg)
		puts arg.to_s.black.on_yellow + 10.chr
	end
end

class String
	def urlencoded?
		return true if self.match(/[%0-9ABCDEF]{3,}/i)
		return false
	end
end

class PluginSkel
end

class FilterSkel

	@@rules = {}

	def rules
		@@rules
	end

	def getRuleFor(arg)
		puts "#{self.class}.#{__method__}(#{arg})"
	end

	alias uri2rule getRuleFor

	def default_rule(arg)
		puts "#{self.class}.#{__method__}(#{arg})"
		#Book.plugin(:name => 'www/load', :data => arg[:uri])
	end
end

class Book

	attr_accessor :title, :author, :language
	
	@@plugin_log = {}
	@@core_plugin_classes = ['www','input','output']

	@@filters_list = {}

	public

	# настроить
	def initialize(arg)
	
		# ~~ преимущественно статическая настройка
	
		# настройки по умолчанию
		@metadata = {
			:title => 'неопределённый заголовок',
			:author => 'неизвестный автор',
			:language => 'ru',
		}
		@options = {
			:depth => 2,
			:total_pages => 10,
			:pages_per_level =>3,
			
			:threads => 1,
			:links_per_level => 5,
			:db_type => 'm',
		}
		@source = []
		@filters = {}
		
		# объединение с пользовательскими настройками
		@metadata.merge!(arg[:metadata]) if not arg[:metadata].nil?
		
		@options.merge!(arg[:options]) if not arg[:options].nil?
		
		if not arg[:source].nil? then
			@source += arg[:source]
			@source.uniq!
		end

		# добавление внутренних настроек
		@@script_name = File.basename(File.realpath(__FILE__)).split('.')[0]
		
		@metadata.merge!({
			:generator_name => @@script_name,
			:generator_version => '0.0.1a',
			:id => SecureRandom.uuid,
		})
		
		@options.merge!({
			:user_agent => 'Ruby/1.9.3, Contacts: aakumykov@yandex.ru'
		})

		# каталоги
		@work_dir = Dir.tmpdir + '/' + @@script_name
		@book_dir = @work_dir + '/' + @metadata[:title].gsub(/\s/,'_')
		
		@text_dir = 'Text'
		@image_dir = 'Images'
		
		# файлы журналов
		#@@error_log = "errors-#{@@script_name}.log"
		#@@alert_log = "alerts-#{@@script_name}.log"
		
		# БД имена
		@db_name = ('m' == @options[:db_type] ) ? ':memory:' : 'db_' + @@script_name + '.sqlite'
		@table_name = 'book_info'

		
		# ~~ преимущественно динамическая настройка

		# создаю каталоги
		( Dir.mkdir(@work_dir) if not Dir.exists?(@work_dir) ) \
		and Msg.cyan("work_dir: #{@work_dir}")

		( Dir.mkdir(@book_dir) if not Dir.exists?(@book_dir)  ) \
		and Msg.cyan("book_dir: #{@book_dir}")

		# удаляю старые файлы
		Dir.new(@book_dir).each { |item| 
			File.delete "#{@book_dir}/#{item}" if item.match(/\.html/) \
			and Msg.debug("удалён #{item}")
		}
		
		# настраиваю БД
		table_def = <<QWERTY
CREATE TABLE #{@table_name} 
(
	id TEXT PRIMARY KEY,
	parent_id TEXT,
	depth INT,
	status TEXT,
	uri TEXT,
	archor_name TEXT,
	title TEXT,
	file_name TEXT,
	file_path TEXT
)
QWERTY

		@db = SQLite3::Database.new(@db_name)
		@db.results_as_hash = true
		
		@db.query("PRAGMA journal_mode=OFF")
		@db.query("DROP TABLE IF EXISTS #{@table_name}")
		@db.query(table_def)
		
		# сохраняю источники в БД
		@source.each { |src|
			self.addSource(src)
		}
		
		
		# внтуренние переменные (куда их?)
		@current_depth = 0
		
		@page_count = 0 
		@page_limit = 0		# 0 (zero) disables this limit
		@page_limit = @options[:total_pages].to_i if not @options[:total_pages].nil?
		
		@errors_limit = 100
		
		@alerts_limit = 0 # пока не используется
			
		@timeout_limit = 60
		
		
		collectFilters
		ap @@filters_list
	end

	def prepare()
		
		Msg.info "#{__method__}()"
		
		# пока не будет готово
		while ( not prepareComplete? ) do
			
			# брать порцию ссылок
			links = getFreshLinks(@current_depth, @options[:threads])
			
			# обрабатывать в потоках
			threads = []
			
			links.each { |lnk|

				source_id = lnk['id']
				source_uri = lnk['uri']
				initial_uri = source_uri
				
				# зарядить нить обработки
				threads << Thread.new(source_uri) { |uri|
				
					thread_uuid = SecureRandom.uuid
					
					#~ source_uri = Book.plugin(
						#~ :name => 'filters/[host]/before_load',
						#~ :uri => initial_uri,
						#~ :data => source_uri,
						#~ :uuid => thread_uuid,
					#~ )
					#~ Msg.cyan(source_uri)

					source_page = Book.plugin(
							:name =>'www/load',
							:data => source_uri,
							:uuid => thread_uuid,
					)
					
					#~ source_page = Book.plugin(
						#~ :name => 'after_load',
						#~ :uri => initial_uri,
						#~ :data => source_page,
						#~ :uuid => thread_uuid,
					#~ )
					
					new_page = processPage(source_page,uri)
					
					savePage(
						:id => source_id,
						:title => new_page[:title],
						:data => new_page[:data],
					)
					
					saveLinks(
						:source_id => source_id,
						:source_page => source_page,
						:source_uri => uri,
					)
					
					setLinkStatus(
						:id 	=>	source_id,
						:title 	=>	new_page[:title],
						:status =>	'processed',
					)
					
					@page_count += 1
				}
			}

			# запустить обработку в нитях
			threads.each { |thr| thr.join }

			displayStatus
			
			@current_depth += 1 if not freshLinksExists?(@current_depth)

			if levelComplete?(@current_depth) then
				Msg.green "на уровне #{@current_depth} обработаны все страницы (#{@options[:pages_per_level]})"
				@current_depth += 1
			end
			
			# пауза перед следующей порцией
			if @options[:threads] > 5 then
				print "Ждём 5 секунд";
				4.times { sleep 1 and print '.' };
				sleep 1 and puts '.'
			end
			
			puts ""
		end		
		
	end

	def create(outputFile='', bookType = 'epub')
		Msg.info "#{__method__}(#{outputFile})"
		
		bookArray = getBookStructure
		
		CreateEpub(
			outputFile,
			bookArray,
			{
				:title=>@title, 
				:author=>@author,
				:language => @language,
				:id => @id, 
				:generator_name => @generator_name,
				:generator_version => @generator_version,
			}
		)
	end


	def self.plugin(arg)
		
		# подготовка и проверки
		name = arg[:name]
		data = arg[:data]
		uuid = arg[:uuid]
    
    Msg.debug("#{self}.#{__method__}(#{arg})")
		
		# проверка имени плагина
		raise "неверное имя плагина: '#{name}'" if not name.match(/^[\w\[\]\/]+$/)
		
		# проверка UUID
		raise "неверный UUID (#{uuid})" if not arg[:uuid].match(/^[abcdef0-9]{8}-[abcdef0-9]{4}-[abcdef0-9]{4}-[abcdef0-9]{4}-[abcdef0-9]{12}$/)
		
		# проверка URI
		#~ begin
			#~ uri = URI::encode(uri) if not uri.urlencoded?
			#~ uri = URI(uri)
		#~ rescue
			#~ raise "invalid URI: #{uri}"
		#~ end
		
		is_core_plugin = @@core_plugin_classes.include?(name.match(/^[\w]+/)[0])
		
		# загрузка файла плагина
		file_name = "./plugins/#{name.downcase}.rb"
		Msg.debug "файл плагина: #{file_name}"
		
		begin
			require file_name
		rescue => e
			if is_core_plugin then
				Msg.error e.message
				exit(1)
			else
				Msg.alert e.message
				return data
			end
		end
		
		# создание и регистрация объекта плагина
		plugin_name = "#{name.split('/').map{|x|x.capitalize}.join}_Plugin"
		Msg.debug "имя плагина: #{plugin_name}"
		
		begin
			plugin = Object.const_get(plugin_name).new
		rescue => e
			if is_core_plugin then
				Msg.error e.message
				exit(1)
			else
				Msg.alert e.message
				return data
			end
		end
		
		# регистрация вызова плагина
		if not @@plugin_log.has_key?(uuid) then
			Msg.debug "новый uuid: #{uuid}"
			@@plugin_log[uuid] = []
		else
			Msg.debug "повторный uuid: #{uuid}"
		end
		
		@@plugin_log[uuid] << name
		
		# работа плагина
		plugin.work(
			:uuid => uuid,
			:data => data,
		)
	end


	def addSource(uri)
		Msg.info "#{__method__}(#{uri})"
				
		id = SecureRandom.uuid
		link = URI::encode(uri) if not uri.urlencoded?
		link = URI(link)
		
		saveURI(
			:id => id, 
			:parent_id => 0, 
			:depth => 0, 
			:uri => link.to_s,
		)

		@filters[link.host] = {
			'links' => [],
			'pages' => {}
		}

		return id
	end
	
	def addFilter(filter)
		Msg.info "#{__method__} for '#{filter.keys.join(', ')}'"
		
		@filters.merge!(filter)
		
		#Msg.debug @filters
	end

	def getBookStructure
		Msg.debug "#{__method__}()"
		
		def getTocItems(arg)
			
			list = []
			
			res = @db.prepare("SELECT * FROM #{@table_name} WHERE parent_id=? AND status='processed'").execute(arg[:parent_id])
			
			res.each { |row|
				list << {
					:id => row['id'],
					:parent_id => row['parent_id'],
					:title => row['title'],
					:file_name => row['file_name'],
					:uri => row['uri'],
					:childs => getTocItems(:parent_id => row['id'])
				}
			}
			
			return list
		end

		return getTocItems(:parent_id => 0)
	end
	
	
	
	private
	
	def prepareComplete?
		
		if  not freshLinksExists?(@current_depth) then
			reason = "все ссылки обработаны"
		
		elsif @current_depth > @options[:depth] then
			reason = "достигнута глубина #{@options[:depth]}"
		
		elsif Msg.errors_count > @errors_limit then
			reason = "достигнут максимум ошибок (#{@errors_limit})"
		
		elsif ( @page_count >= @page_limit) and (0 != @page_limit)  then
			reason = "достигнут максимум страниц (#{@page_limit})"
		
		else
			return false
		end
		
		#Msg.info "============== #{reason} =============="
		Msg.info "============== подготовка завершена =============="
		displayStatus
		return true
	end

	def freshLinksExists?(depth)
		#Msg.debug "#{__method__}(#{depth})"
		
		q = "SELECT * FROM #{@table_name} WHERE depth='#{depth}' AND status='fresh'"
		res = @db.execute(q)
		res = res.count != 0
		
		#Msg.debug  "#{__method__}(depth #{depth}) ==> #{res}"
		
		return res
	end

	def levelComplete?(depth)
		Msg.debug "#{__method__}()"
		
		q = "SELECT  * FROM #{@table_name} WHERE depth=? AND status='processed' "
		
		res = @db.prepare(q).execute(depth)
		
		return ( res.count >= @options[:pages_per_level] and 0 != @options[:pages_per_level] )
	end

	def getFreshLinks( depth, amount )
		Msg.debug "#{__method__}(#{depth},#{amount})"
		
		q = "SELECT * FROM #{@table_name} WHERE status='fresh' AND depth=#{depth} LIMIT #{amount}"
		res = @db.execute(q)
		
		#res.each { |row| Msg.info "#{row['uri']}" }
		
		return res
	end
	
	# === Parameters:
	# * _source_page_
	# * _source_uri_
	# === Returns: 
	# string
	def processPage(source_page,source_uri)
		Msg.debug(__method__)
		
		page_title = extractTitle(source_page)
		 Msg.green "заголовок: #{page_title}"
		
		page_body = extractBody(source_page,source_uri)

		new_page = composePage(page_title,page_body)

		new_page = tidyPage(new_page)
		
		{
			:title => page_title,
			:data => new_page,
		}
	end
	
	def saveLinks(arg)
		Msg.debug("#{arg}")
		
		new_links = extractLinks(arg[:source_page],arg[:source_uri])

		new_links.each { |lnk|
			saveURI( 
				:id => SecureRandom.uuid, 
				:parent_id => arg[:source_id], 
				:depth => @current_depth+1, 
				:uri => lnk,
			)
		}
	end
	
	def tidyPage input_file
		stdin, stdout, stderr = Open3.popen3 "tidy -utf8 -numeric -quiet -asxhtml --drop-proprietary-tags yes --force-output yes --doctype omit #{input_file}"
		output   = stdout.read.strip
		warnings = stderr.read.split("\n").select {|line| line =~ /line \d+ column \d+ - Warning:/ }
		return output
	end
	
	def extractLinks(html_data,uri,filter='')
		Msg.debug "#{__method__} from page '#{uri}'"
		
		links = collectLinks(uri,html_data)
		#puts "collected: #{links.size}"
		
		filter = getFilterFor(uri,'links')
		
		links = filterLinks(links,filter)
		#links.each { |lnk| puts URI::decode(lnk) }

		return links
	end
	
	def saveURI(arg)
		Msg.debug "#{__method__}(#{arg})"
		
		encoded_uri = arg[:uri].urlencoded? ? arg[:uri] : URI::encode(arg[:uri])
		
		q_check = "SELECT * FROM #{@table_name} WHERE uri = ?"
		res = @db.prepare(q_check).execute(encoded_uri)
		
		if res.count > 0 then
			Msg.debug "Дубликат #{arg[:uri]}"
			return false
		end
		
		q = "INSERT INTO #{@table_name} (id, parent_id, depth, status, uri) VALUES (?, ?, ?, ?, ?)"
		
		begin
			@db.prepare(q).execute(
				arg[:id],
				arg[:parent_id],
				arg[:depth],
				'fresh',
				encoded_uri
			)
		rescue
			Msg.error "'#{q}'"
		end
	end
	
	def composePage(title,body)
		return <<DATA
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
     "http://www.w3.org/TR/html4/loose.dtd">
<html>
<head>
<meta http-equiv='Content-Type' Content='text/html;charset=UTF-8'/>
<title>#{title}</title>
</head>
<body>
#{body}
</body>
</html>
DATA
	end
	
	def savePage(arg)
		id = arg[:id]
		title = arg[:title]
		data = arg[:data]
		
		file_name = arg[:id] + ".html"
		file_path = @book_dir + "/" + file_name
		
		Msg.info "#{__method__}('#{title}', '#{file_name}'), data size: #{data.size}"

		begin
			File.open(file_path,'w') { |file|
			file.write(data)
		}
		rescue
			Msg.error "запись #{title} в файл #{file_path}"
		end


		begin
			@db.prepare("UPDATE #{@table_name} SET file_path=? WHERE id=? ").execute(file_path, id)
		rescue
			Msg.error "сохранение в БД file_path='#{file_path}') для '#{title}'"
		end


		begin
			@db.prepare("UPDATE #{@table_name} SET file_name=? WHERE id=? ").execute(file_name, id)
		rescue
			Msg.error "сохранение в БД file_name='#{file_name}' для '#{title}'"
		end
	end
	
	def setLinkStatus(arg)
		Msg.info "#{__method__}(), #{arg[:title]}, #{arg[:status]}, #{arg[:id]}"
		
		q = "UPDATE #{@table_name} SET status='#{arg[:status]}', title='#{arg[:title]}' WHERE id='#{arg[:id]}'"
		
		# писать в БД до победного конца (что-то пошли дедлоки)
		res = nil
		while res.nil? do
			begin
				res = @db.prepare(q).execute()
			rescue => e
				Msg.error e.message
			end
		end
	end
	
	
	# методы второго уровня
	def getOptions(id)
		Msg.debug "#{__method__}(#{id})"
		
		if @options.has_key?(id) then
			return @options[id]
		else
			return {}
		end
	end

	def getFilterFor(uri,mode)
		Msg.debug "#{__method__}(#{uri},'#{mode}')"
		
		host = URI(uri).host
		
		case mode
			when 'links'
				Msg.debug "items in filter: #{@filters[host]['links'].size}"
				
				return @filters[host]['links']

			when 'page'
				@filters[host]['pages'].each { |pattern,rule|
					return rule if uri.match(pattern) 
				}
				return '/'

			else
				Msg.error "неизвестный режим '#{mode}'"
				return nil
		end
	end


	def collectLinks(uri,page)
		Msg.info "#{__method__}(#{ URI::decode(uri) })"

		base_uri = URI(uri)

		all_links = []

		anchors = Nokogiri::HTML(page).xpath('//a').map { |i|
			
			i['href'].nil? and next
			i['href'].empty? and next
			
			i['href'].strip!
			href = i['href']
			#href = URI::decode(i['href'])
			#puts 'decoded href: ' + href.to_s
			
			all_links << href
		}
		
		
		www_links = []
		
		count = 0
		all_links.each { |item|
		
			break if @options[:links_per_level] != 0 and count > @options[:links_per_level]
			
			next if item.match(/^mailto:/)
			next if item.match(/action=edit/)

			item_orig = item
			
			begin
				item = URI::decode(item)
			rescue
				Msg.alert "кривая ссылка для urldecode: #{item_orig.encode()}"
				next
			end
			
			begin
				item = URI::encode(item)
			rescue
				Msg.alert "кривая ссылка для urlencode: #{item_orig.encode()}"
				next
			end
						
			www_links << item
			
			count += 1
		}
		
		
		normalized_links = []
		
		www_links.each { |item|
		
			begin
				uri = URI(item)
			rescue
				Msg.alert "кривая ссылка ВТОРОГО уровня: #{item.encode()}"
				next
			end
		
			uri.scheme = base_uri.scheme if uri.scheme.to_s.empty?
			uri.host = base_uri.host if uri.host.to_s.empty?
		
			normalized_links << uri.to_s
		}
		
		normalized_links.compact!
		normalized_links.uniq!
		
		Msg.debug "raw #{all_links.count} / unique #{normalized_links.count}"
		#ap links
		
		return normalized_links
	end

	def filterLinks(links,filter)
		Msg.debug "#{__method__}(input: #{links.size})"

		return links if filter.size == 0

		selected_links = []

		links.each { |lnk|
			
			filter.each { |pat|
			
				res = lnk.match(pat) ? true : false
				
				#puts "#{res.to_s.upcase}: #{lnk}  [ #{pat} ]"
				
				if (res) then
					selected_links << lnk
					break
				end
			}
		}
		
		selected_links.uniq!
		Msg.debug "#{__method__}(output: #{selected_links.size})"
		#ap selected_links
		
		return selected_links
	end
	
	def tidyPage(html_data)
		i,o,e,t = Open3.popen3("tidy -numeric -utf8 -asxhtml -quiet --drop-proprietary-attributes yes --force-output yes --doctype omit")
		i.puts html_data
		i.close
		o.read
	end
	
	def extractBody(html_data,uri)
		Msg.debug "#{__method__}()"
		
		filter = getFilterFor(uri,mode='page')
		Msg.debug("page filter: #{filter}")
		
		res = Nokogiri::HTML(html_data).xpath(filter).first.to_s
		
		return res
	end

	def extractTitle(html_data)
		Msg.debug("#{__method__}() from " + html_data.size.to_s + "-bytes html")
		res = html_data.match(%r|<title[^>]*>(?<title>.*)<\s*/\s*title\s*>|im)
		return '* нет заголовка *' if res.nil?
		return res[:title].strip
	end

	def displayStatus
		Msg.info "====  глубина #{@current_depth} ===="
		Msg.info "==== страниц #{@page_count} ===="
		Msg.info "==== ошибок #{Msg.errors_count} ===="
		Msg.info "==== предупреждений #{Msg.alerts_count} ===="
	end


	def file2object(file_path)
		file_name = File.basename(file_path)
		class_name = file_name.gsub(/\.rb$/,'').split('_').map{|n|n.capitalize}.join
		
		Msg.debug("#{self.class}.#{__method__}(), path: #{file_path}, name: #{file_name}, class: #{class_name}")
		
		begin
			require file_path
			obj = Object.const_get(class_name).new
			return obj
		rescue => e
			Msg.error e.message
			return nil
		end
	end


	def collectFilters
		Msg.debug("#{self.class}.#{__method__}()")

		if not @@filters_list.empty? then
			Msg.blue("список фильтров уже составлен")
			return true
		end
		
		dir = './plugins/www/filters'
		files = Dir.entries(dir).collect{|item| item if item.match(/^\w+_filter.rb$/)}
		files.delete('default_filter.rb')
		files.compact!
		
		files.each {|file_name|
			file_path = dir + '/' + file_name
			filter = file2object(file_path)

			filter.rules.each_key {|pattern|
				if not @@filters_list.key?(pattern) then
					@@filters_list[pattern] = file_path
				else
					Msg.error("дубликат ключа '#{pattern}: присутствует значение '#{@@filters_list[pattern]}', добавляется #{file_path}")
				end
			}
		}
	end
	
	def uri2filter(uri)
		Msg.blue "#{self.class}.#{__method__}(#{uri})"
		
		@@filters_list.each { |pattern,file_path|
		
			if uri.match(pattern) then
				filter = file2object(file_path)
				return filter
			end
		}
		
		filter = file2object('./plugins/www/filters/default.rb')
	end

	#alias getFilterFor uri2filter


	def CreateEpub (output_file, bookArray, metadata)
		Msg.info "#{__method__}('#{output_file}')"
		
		#puts "\n=================================== bookArray =================================="
		#ap bookArray
		
		# arg = { :bookArray, :metadata }
		def MakeNcx(arg)
			Msg.debug "#{__method__}()"
			
			# arg = { :bookArray, :depth }
			def MakeNavPoint(bookArray, depth)
				
				navPoints = ''
				
				bookArray.each { |item|
					#puts "===================== item ========================"
					#ap item
					
					id = Digest::MD5.hexdigest(item[:id])
					
					if not item[:childs].empty? then
						
						dir_id = SecureRandom.uuid
					
						navPoints += <<NCX
<navPoint id='#{dir_id}'>
	<navLabel>
		<text>>> #{item[:title]}</text>
	</navLabel>
	<content src='#{@text_dir}/#{item[:file_name]}'/>

	<navPoint id='#{id}' playOrder='#{depth}'>
		<navLabel>
			<text>#{item[:title]}</text>
		</navLabel>
		<content src='#{@text_dir}/#{item[:file_name]}'/>
	</navPoint>
NCX
						depth += 1
						
						navPoints += MakeNavPoint(item[:childs], depth)[:xml_tree]
						
						navPoints += <<NCX
</navPoint>
NCX
					else
						navPoints += <<NCX
	<navPoint id='#{id}' playOrder='#{depth}'>
		<navLabel>
			<text>#{item[:title]}</text>
		</navLabel>
		<content src='#{@text_dir}/#{item[:file_name]}'/>
	</navPoint>
NCX
						depth += 1
					end
				}
				
				return { 
					:xml_tree => navPoints,
					:depth => depth,
				}
			end


			nav_data = MakeNavPoint(arg[:bookArray],0)
			metadata = arg[:metadata]

			ncx = <<NCX_DATA
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
<head>
	<meta content="FB2BookID" name="dtb:uid"/>
	<meta content="1" name="dtb:#{nav_data[:depth]}"/><!-- depth -->
	<meta content="0" name="dtb:#{nav_data[:depth]}"/><!-- pages count -->
	<meta content="0" name="dtb:#{nav_data[:depth]}"/><!-- max page number -->
</head>
<docTitle>
	<text>#{@metadata[:title]}</text>
</docTitle>
<navMap>
#{nav_data[:xml_tree]}</navMap>
</ncx>
NCX_DATA

			return ncx
		end
		
		# arg = { :bookArray, :metadata }
		def MakeOpf(arg)
			Msg.debug "#{__method__}()"
			
			# manifest - опись содержимого
			def makeManifest(bookArray)
				Msg.debug "#{__method__}()"
				
				output = ''
				
				bookArray.each{ |item|
					id = 'opf_' + Digest::MD5.hexdigest(item[:id])
					output += <<MANIFEST
	<item href='#{@text_dir}/#{item[:file_name]}' id='#{id}'  media-type='application/xhtml+xml' />
MANIFEST
					output += self.makeManifest(item[:childs]) if not item[:childs].empty?
				}
				
				return output
			end
			
			# spine - порядок пролистывания
			def makeSpine(bookArray)
				Msg.debug "#{__method__}()"
				
				output = ''

				bookArray.each { |item|
					id = 'opf_' + Digest::MD5.hexdigest(item[:id])
					output += "\n\t<itemref idref='#{id}' />";
					output += self.makeSpine(item[:childs]) if not item[:childs].empty?
				}
				
				return output
			end
			
			# guide - это семантика файлов
			def makeGuide(bookArray)
				Msg.debug "#{__method__}()"
				
				output = ''
				
				bookArray.each { |item|
					output += "\n\t<reference href='#{@text_dir}/#{item[:file_name]}' title='#{item[:title]}' type='text' />"
					output += self.makeGuide(item[:childs]) if not item[:childs].empty?
				}
				
				return output
			end
				
			manifest = makeManifest(arg[:bookArray])
			spine = makeSpine(arg[:bookArray])
			guide = makeGuide(arg[:bookArray])

			metadata = arg[:metadata]
			
			opf = <<OPF_DATA
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
	<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
		<dc:identifier id="BookId" opf:scheme="UUID">urn:uuid:#{@metadata[:id]}</dc:identifier>
		<dc:title>#{@metadata[:title]}</dc:title>
		<dc:creator opf:role="aut">#{@metadata[:author]}</dc:creator>
		<dc:language>#{@metadata[:language]}</dc:language>
		<meta name="#{@metadata[:generator_name]}" content="#{@metadata[:generator_version]}" />
	</metadata>
	<manifest>
#{manifest}
		<item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml" />
	</manifest>
	<spine toc="ncx">#{spine}
	</spine>
	<guide>#{guide}
	</guide>
</package>
OPF_DATA
			return opf
		end
		
		
		def createZipFile(zip_file, source_path)
			Msg.info "#{__method__}(#{zip_file},#{source_path})"
			Find.find(source_path) do |input_item|
				Zip::File.open(zip_file, Zip::File::CREATE) do |zipfile|
					virtual_item = input_item.strip.gsub( source_path, '' ).gsub(/^[\/]*/,'')
					next if virtual_item.empty?
					zipfile.add(virtual_item, input_item)
				end
			end
		end
		
		
		# создание дерева каталогов под epub-книгу
		epub_dir = @book_dir + '/' + 'epub'
		meta_dir = epub_dir + '/META-INF'
		oebps_dir = epub_dir + '/OEBPS'
		oebps_text_dir = oebps_dir + '/Text'
		
		#~ begin
			#~ FileUtils.rm_rf(epub_dir)
		#~ rescue
			#~ raise "Не могу удалить '#{epub_dir}' с подкаталогами"
		#~ end
		
		Dir.mkdir(epub_dir) if not Dir.exists?(epub_dir)
		Dir.mkdir(meta_dir) if not Dir.exists?(meta_dir)
		Dir.mkdir(oebps_dir) if not Dir.exists?(oebps_dir)
		Dir.mkdir(oebps_text_dir) if not Dir.exists?(oebps_text_dir)
		
		# создание служебных(?) файлов
		File.open(epub_dir + '/mimetype','w') { |file|
			file.write('application/epub+zip')
		}
		File.open(epub_dir + '/META-INF/container.xml','w') { |file|
			file.write <<DATA
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
   </rootfiles>
</container>
DATA
		}
		
		# создание и запись NCX и OPF
		ncxData = MakeNcx(:bookArray => bookArray,:metadata => metadata)
		opfData = MakeOpf(:bookArray => bookArray,:metadata => metadata)
		
		File.open(epub_dir + '/OEBPS/toc.ncx','w') { |file|
			file.write(ncxData)
		}
		
		File.open(epub_dir + '/OEBPS/content.opf','w') { |file|
			file.write(opfData)
		}
		
		Msg.debug "\n=================================== NCX =================================="
		Msg.debug ncxData
		Msg.debug "\n=================================== OPF =================================="
		Msg.debug opfData
		
		# Перемещаю html-файлы в дерево EPUB
		Dir.entries(@book_dir).each { |file_name|
			File.rename(@book_dir + '/' + file_name, oebps_text_dir + '/' + file_name) if file_name.match(/\.html$/)
		}
		
		# Создаю EPUB-файл
		createZipFile( output_file, epub_dir + '/')
	end


end


start_time = Time.now

epub_file = 'test-book.epub'
File.delete(epub_file) if File.exists?(epub_file)

book = Book.new(
	:metadata => {
		:title => 'test book',
		:author => 'разные авторы',
		:language => 'ru',
	},
	:source => [
		'https://ru.wikipedia.org/wiki/Кварк',
		#'https://ru.wikipedia.org/wiki/Нейтрино',
		#'http://opennet.ru'
	],
	:options => {
		:depth => 2,
		:total_pages => 1,
		:pages_per_level => 3,
		
		:threads => 1,
		:links_per_level => 10,
		:db_type => 'f',
	}
)

book.addFilter({
	'opennet.ru' => {
		'links' => [
			'(www\.)?opennet\.ru\/opennews\/art\.shtml\?num=[\d]+'
		],
		'pages' => {
			'\/opennet\.ru(\/)?$' => '//body/table[1]//table[1]',
			'(www\.)?opennet\.ru\/opennews\/art\.shtml\?num=[\d]+' => '//body/table[1]//table[1]',		
		}
	},
	'ru.wikipedia.org' => {
		'links' => [
			'ru\.wikipedia\.org\/wiki\/[^/:]+$',
		],
		'pages' => {
			'ru\.wikipedia\.org\/wiki\/[^/]+' => "//div[@id='content']"
		}
	}
})

book.prepare()

book.create('test-book.epub')


puts "", "время выполнения: #{Time.now - start_time}"
