#!/usr/bin/env ruby
# coding: utf-8

# СДЕЛАТЬ:
# * упорядочить public / private
# * escapeshell{arg,cmd}
#
# Вопросы для решения:
# * индивидуальная обработка глубины каждого источника
# * дубликаты ссылок в БД
# * производительность БД
# * нормализация URI (для использования в качестве хэша)
# * жизнь кодировок
# * вывод ошибок в stderr
# * при ошибке сохранения ссылки всё равно устанавливается статус 'processed'
#
# ОШИБКИ:
# * знак # кодируется в %23, который потом не срабатывает при открытии ссылки
#
# ОСОБЕННОСТИ:
# * ранжирование фильтров по частоте срабатывания
#
# ЖУРНАЛ ИЗМЕНЕНИЙ:
# * 2015.06.21 переписал collectLinks(); перевёл с SimpleURI обратно на URI; исключил из обработки ссылки с 'action=edit'
#
#

system 'clear'

require 'rubygems'
require 'open-uri'
require 'sqlite3'
require 'securerandom'
require 'digest/md5'
require 'tmpdir'
require 'nokogiri'
require 'curl'	# must be before 'colorize'
require 'colorize'	# must be after 'curl' for right colors
require 'awesome_print'
require 'uri'


module Msg

	def msg_debug(arg)
		#puts arg.to_s.white + 10.chr
	end

	def msg_info(arg)
		puts arg.to_s + 10.chr
	end

	def msg_error(arg)
		@errors_count += 1
		arg = arg.to_s
		puts ("ОШИБКА: " + arg).red + 10.chr
		File.open(@error_log,'w') if not File.exists?(@error_log)
		File.open(@error_log,'a') { |file| file.write(arg+10.chr) }
	end
	
	def msg_alert(arg)
		@alerts_count += 1
		arg = arg.to_s
		puts ("###: " + arg).yellow + 10.chr
		File.open(@alert_log,'w') if not File.exists?(@alert_log)
		File.open(@alert_log,'a') { |file| file.write(arg+10.chr) }
	end
	
	def msg_info_blue(arg)
		puts arg.to_s.blue + 10.chr
	end
	
	def msg_info_green(arg)
		puts arg.to_s.green + 10.chr
	end
	
	def msg_info_cyan(arg)
		puts arg.to_s.cyan + 10.chr
	end
	
	def msg_ahtung(arg)
		puts arg.to_s.black.on_yellow + 10.chr
	end
end

class String
	def urlencoded?
		return true if self.match(/[%0-9ABCDEF]{3,}/i)
		return false
	end
end

class Book

	include Msg

	attr_accessor :title, :author, :language
	
	# методы первого уровня
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
			:depth => 5,
			:total_pages => 15,
			:pages_per_level =>3,
			
			:threads => 1,
			:links_per_level => 5,
			:db_type => 'm',
		}
		@source = []
		@filters = {}
		
		# объединение с пользовательскими настройками
		@metadata.merge!(arg[:metadata]) if not arg[:metadata].nil?
		@metadata.merge!(arg[:option]) if not arg[:option].nil?
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
		
		# файлы журналов
		@error_log = "errors-#{@@script_name}.log"
		@alert_log = "alerts-#{@@script_name}.log"
		
		# БД имена
		@db_name = ('m' == @options[:db_type] ) ? ':memory:' : 'db_' + @@script_name + '.sqlite'
		@table_name = 'book_info'

		
		# ~~ преимущественно динамическая настройка

		# создаю каталоги
		Dir.mkdir(@work_dir) if not Dir.exists?(@work_dir) \
		and msg_debug("work_dir: #{@work_dir}")

		Dir.mkdir(@book_dir) if not Dir.exists?(@book_dir) \
		and msg_debug("work_dir: #{@book_dir}")

		# удаляю старые файлы
		Dir.new(@book_dir).each { |item| 
			File.delete "#{@book_dir}/#{item}" if item.match(/\.html/) \
			and msg_debug("удалён #{item}")
		}

		File.delete(@error_log) if File.exists?(@error_log) \
		and msg_debug("удалён #{@error_log}")
		
		File.delete(@alert_log) if File.exists?(@alert_log) \
		and msg_debug("удалён #{@alert_log}")
		
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
	file TEXT
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
		@target_depth = 0
		@target_depth = @options[:depth].to_i if not @options[:depth].nil?
		
		@page_count = 0 
		@page_limit = 0		# 0 (zero) disables this limit
		@page_limit = @options[:total_pages].to_i if not @options[:total_pages].nil?
		
		@pages_per_level = 0 # 0 == unlimited
		@pages_per_level = @options[:pages_per_level] if not @options[:pages_per_level].nil?
		
		# links_per_level нужен на период тестирования для ограничения нагрузки на файловую БД
		@links_per_level = 0 # 0 == unlimited
		@links_per_level = @options[:links_per_level] if not @options[:links_per_level].nil?
		
		@errors_count = 0
		@errors_limit = 100
		
		@alerts_count = 0 # только для информации
		@alerts_limit = 0 # пока не используется
		
		@timeout_limit = 60
	end

	def addSource(uri)
		msg_info "#{__method__}(#{uri})"
				
		id = SecureRandom.uuid
		link = URI::encode(uri) if not uri.urlencoded?
		link = URI(link)
		
		saveLink(id, 0, 0, link.to_s)

		@filters[link.host] = {
			'links' => [],
			'pages' => {}
		}

		return id
	end
	
	def addFilter(filter)
		msg_info "#{__method__} for '#{filter.keys.join(', ')}'"
		
		@filters.merge!(filter)
		
		#msg_debug @filters
	end

	def prepare()
		
		msg_info "#{__method__}()"
		
		# пока не будет готово
		#until ( prepareComplete? ) do
		while ( not prepareComplete? ) do
				
			msg_debug "CURRENT: pages #{@page_count}, depth #{@current_depth}"
			
			# брать порцию ссылок
			links = getFreshLinks(@current_depth, @threads)
			
			# и обрабатывать (в потоках)
			threads = []
			
			links.each { |row|

				source_id = row['id']
				source_uri = row['uri']
				
				# зарядить нить обработки
				threads << Thread.new(source_uri) { |uri|

					# получишь страницу
					source_page = loadPage(uri)
					
					# выделишь заголовок
					page_title = extractTitle(source_page)
					msg_info_green "заголовок: #{page_title}"
					
					# обрежешь и сохранишь страницу
					page_body = extractBody(source_page,source_uri)
					
					# сохранишь страницу
					savePage({
						:id => source_id,
						:title => page_title,
						:body => page_body,
					})
					
					# выделишь и сохранишь ссылки
					new_links = extractLinks(source_page,uri)

					new_links.each { |link|
						saveLink( 
							SecureRandom.uuid, 
							source_id, 
							@current_depth+1, 
							link 
						)
					}
					
					setLinkStatus(source_id,{:status=>'processed',:title=>page_title})
					
					@page_count += 1
				}
			}
			
			# запустить обработку в нитях
			threads.each { |thr| thr.join }
		
			displayStatus
			
			@current_depth += 1 if not freshLinksExists?(@current_depth)

			if depthComplete?(@current_depth) then
				msg_info_green "на уровне #{@current_depth} обработаны все страницы (#{@pages_per_level})"
				@current_depth += 1
			end
			
			# пауза перед следующей порцией
			if @threads > 5 then
				print "Ждём 5 секунд";
				4.times { sleep 1 and print '.' };
				sleep 1 and puts '.'
			end
			
			puts ""
		end		
		
	end
	
	def getBookStructure
		msg_debug "#{__method__}()"
		
		def getTocItems(id)
			list = []
			res = @db.prepare("SELECT * FROM #{@table_name} WHERE parent_id=? AND status='processed'").execute(id)
			res.each { |row|
				list << {
					:id => row['id'],
					:title => row['title'],
					:file => row['file'],
					:uri => row['uri'],
					:childs => getTocItems(row['id'])
				}
			}
			return list
		end

		res = @db.query("SELECT * FROM #{@table_name} WHERE depth=0 AND status='processed'")
		
		if 0 == res.count then
			msg_alert "похоже, что книга пуста"
			return {}
		else
			res.reset # ВАЖНО: сбрасывается курсор после 'res.count'
			root_id = res.next['id']
			return getTocItems(root_id)
		end
	end
	
	def create(file='')
		msg_info "#{__method__}(#{file})"
		
		bookArray = getBookStructure
		
		CreateEpub(
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


	private
	
	def prepareComplete?
	
		#return @current_depth == @target_depth
		
		if  not freshLinksExists?(@current_depth) then
			reason = "все ссылки обработаны"
		
		elsif @current_depth > @target_depth then
			reason = "достигнута глубина #{@target_depth}"
		
		elsif @errors_count > @errors_limit then
			reason = "достигнут максимум ошибок (#{@errors_limit})"
		
		elsif ( @page_count >= @page_limit) and (0 != @page_limit)  then
			reason = "достигнут максимум страниц (#{@page_limit})"
		
		else
			return false
		end

		return true
	end

	def freshLinksExists?(depth)
		#msg_debug "#{__method__}(#{depth})"
		
		q = "SELECT * FROM #{@table_name} WHERE depth='#{depth}' AND status='fresh'"
		res = @db.execute(q)
		res = res.count != 0
		
		#msg_debug  "#{__method__}(depth #{depth}) ==> #{res}"
		
		return res
	end

	def depthComplete?(depth)
		msg_debug "#{__method__}()"
		
		q = "SELECT  * FROM #{@table_name} WHERE depth=? AND status='processed' "
		
		res = @db.prepare(q).execute(depth)
		
		return ( res.count >= @pages_per_level and 0 != @pages_per_level )
	end

	def getFreshLinks ( depth, amount )
		msg_info "#{__method__}(#{depth},#{amount})"
		
		q = "SELECT * FROM #{@table_name} WHERE status='fresh' AND depth=#{depth} LIMIT #{amount}"
		res = @db.execute(q)
		
		#res.each { |row| msg_info "#{row['uri']}" }
		
		return res
	end
	
	def loadPage(uri)
		msg_info_blue "#{__method__}('#{uri.urlencoded? ? URI::decode(uri) : uri}')"
		
		curl = CURL.new
		curl.user_agent = @options[:user_agent]
		page = curl.get(uri)

		return page
	end
	
	def extractLinks(html_data,uri,filter='')
		msg_debug "#{__method__} from page '#{uri}'"
		
		links = collectLinks(uri,html_data)
		#puts "collected: #{links.size}"
		
		filter = getFilterFor(uri,'links')
		
		links = filterLinks(links,filter)
		#links.each { |lnk| puts URI::decode(lnk) }

		return links
	end
	
	def saveLink(id, parent_id, depth, uri)
		msg_debug "#{__method__}(#{id}, #{parent_id}, #{depth}, #{uri})"
		
		uri = URI::encode(uri) if not uri.urlencoded?
		
		q_check = "SELECT * FROM #{@table_name} WHERE uri = ?"
		res = @db.prepare(q_check).execute(uri)
		
		if res.count > 0 then
			msg_debug "Дубликат #{uri}"
			return false
		end
		
		q = "INSERT INTO #{@table_name} (id, parent_id, depth, status, uri) VALUES (?, ?, ?, ?, ?)"
		
		begin
			@db.prepare(q).execute(
				id,
				parent_id,
				depth,
				'fresh',
				uri
			)
		rescue
			msg_error "'#{q}'"
		end
	end
	
	def savePage(arg)
		id = arg[:id]
		title = arg[:title]
		page_body = arg[:body]
		
		file_name = @book_dir+"/"+arg[:id]+".html"
		
		msg_info "#{__method__}('#{title}', '#{file_name}'), body size: #{page_body.size}"

		begin
			File.open(file_name,'w') { |file|
			file.write <<QWERTY
 <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
     "http://www.w3.org/TR/html4/loose.dtd">
<html>
<head>
<meta http-equiv='Content-Type' Content='text/html;charset=UTF-8'>
<title>#{title}</title>
</head>
<body>
#{page_body}
</body>
</html>
QWERTY
		}
		rescue
			msg_error "запись #{title} в файл #{file_name}"
		end
		
		begin
			q = "UPDATE #{@table_name} SET file='#{file_name}' WHERE id='#{id}'"
			@db.query(q)
		rescue
			msg_error "сохранение в БД имени файла (#{file_name}) для '#{title}'"
		end
	end
	
	def setLinkStatus(id,options)
		msg_info "#{__method__}(), #{options[:title]}, #{options[:status]}, #{id}"
		
		q = "UPDATE #{@table_name} SET status='#{options[:status]}', title='#{options[:title]}' WHERE id='#{id}'"
		
		# писать в БД до победного конца (что-то пошли дедлоки)
		res = nil
		while res.nil? do
			begin
				res = @db.prepare(q).execute()
			rescue => e
				msg_error e.message
			end
		end
	end
	
	
	# методы второго уровня
	def getOptions(id)
		msg_debug "#{__method__}(#{id})"
		
		if @options.has_key?(id) then
			return @options[id]
		else
			return {}
		end
	end

	def getFilterFor(uri,mode)
		msg_debug "#{__method__}(#{uri},'#{mode}')"
		
		host = URI(uri).host
		
		case mode
			when 'links'
				msg_debug "items in filter: #{@filters[host]['links'].size}"
				
				return @filters[host]['links']

			when 'page'
				@filters[host]['pages'].each { |pattern,rule|
					return rule if uri.match(pattern) 
				}
				return '/'

			else
				msg_error "неизвестный режим '#{mode}'"
				return nil
		end
	end


	def collectLinks(uri,page)
		msg_info "#{__method__}(#{ URI::decode(uri) })"

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
		
			break if @links_per_level != 0 and count > @links_per_level
			
			next if item.match(/^mailto:/)
			next if item.match(/action=edit/)

			item_orig = item
			
			begin
				item = URI::decode(item)
			rescue
				msg_alert "кривая ссылка для urldecode: #{item_orig.encode()}"
				next
			end
			
			begin
				item = URI::encode(item)
			rescue
				msg_alert "кривая ссылка для urlencode: #{item_orig.encode()}"
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
				msg_alert "кривая ссылка ВТОРОГО уровня: #{item.encode()}"
				next
			end
		
			uri.scheme = base_uri.scheme if uri.scheme.to_s.empty?
			uri.host = base_uri.host if uri.host.to_s.empty?
		
			normalized_links << uri.to_s
		}
		
		normalized_links.compact!
		normalized_links.uniq!
		
		msg_debug "raw #{all_links.count} / unique #{normalized_links.count}"
		#ap links
		
		return normalized_links
	end

	def filterLinks(links,filter)
		msg_debug "#{__method__}(input: #{links.size})"

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
		msg_debug "#{__method__}(output: #{selected_links.size})"
		#ap selected_links
		
		return selected_links
	end
	
# /html/body/table[1]/tbody/tr/td[2]/table/tbody/tr/td/table
# html body table tbody tr td table.ttxt tbody tr td table

	
	def extractBody(html_data,uri)
		msg_debug "#{__method__}()"
		
		filter = getFilterFor(uri,mode='page')
		msg_debug("page filter: #{filter}")
		
		res = Nokogiri::HTML(html_data).xpath(filter).first.to_s
		
		return res
	end

	def extractTitle(html_data)
		msg_debug("#{__method__}() from " + html_data.size.to_s + "-bytes html")
		res = html_data.match(%r|<title[^>]*>(?<title>.*)<\s*/\s*title\s*>|im)
		return '* нет заголовка *' if res.nil?
		return res[:title].strip
	end

	def displayStatus
		msg_info_blue "====  глубина #{@current_depth}===="
		msg_info_blue "==== страниц #{@page_count}===="
		msg_info_blue "==== ошибок #{@errors_count}===="
		msg_info_blue "==== предупреждений #{@alerts_count}===="
	end


	def CreateEpub (bookArray, metadata)
		msg_info "#{__method__}()"
		
		puts "\n=================================== bookArray =================================="
		ap bookArray
		
		def MakeNcx(arg)
			msg_debug "#{__method__}()"
			
			depth = arg[:depth].nil? ? 0 : arg[:depth]
			bookArray = arg[:bookArray]
			metadata = arg[:metadata]
			
			navPoints = ''
			
			bookArray.each { |item|
				id = Digest::MD5.hexdigest(item[:id])
				
				navPoints += <<NCX
<navPoint id='#{id}' playOrder='#{depth}'>
	<navLabel>
		<text>#{item[:title]}</text>
	</navLabel>
<content src='#{item[:file]}'/>
NCX
				
				navPoints += self.MakeNcx(
							{
								:bookArray => item[:childs], 
								:depth => depth,
								:metadata => metadata,
							}
						) if not item[:childs].empty?
				
				navPoints += "</navPoint>\n"
				
				depth += 1
			}

			ncx = <<NCX_DATA
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
<head>
	<meta content="FB2BookID" name="dtb:uid"/>
	<meta content="1" name="dtb:#{depth}"/><!-- depth -->
	<meta content="0" name="dtb:#{depth}"/><!-- pages count -->
	<meta content="0" name="dtb:#{depth}"/><!-- max page number -->
</head>
<docTitle>
	<text>#{metadata[:title]}</text>
</docTitle>
<navMap>#{navPoints}
</navMap>
</ncx>
NCX_DATA

			return ncx
		end
		
		def MakeOpf(arg)
			msg_debug "#{__method__}()"
			
			# manifest - опись содержимого
			def makeManifest(bookArray)
				msg_debug "#{__method__}()"
				
				output = ''
				
				bookArray.each{ |item|
					id = Digest::MD5.hexdigest(item[:id])
					output += <<MANIFEST
	<item href='#{item[:uri]}' id='#{id}'  media-type='application/xhtml+xml' />
MANIFEST
					output += self.makeManifest(item[:childs]) if not item[:childs].empty?
				}
				
				return output
			end
			
			# spine - порядок пролистывания
			def makeSpine(bookArray)
				msg_debug "#{__method__}()"
				
				output = ''

				bookArray.each { |item|
					id = Digest::MD5.hexdigest(item[:id])
					output += "\n\t<itemref idref='#{id}' />";
					output += self.makeSpine(item[:childs]) if not item[:childs].empty?
				}
				
				return output
			end
			
			# guide - это семантика файлов
			def makeGuide(bookArray)
				msg_debug "#{__method__}()"
				
				output = ''
				
				bookArray.each { |item|
					output += "\n\t<reference href='#{item[:file]}' title='#{item[:title]}' type='text' />"
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
    <dc:identifier id="BookId" opf:scheme="UUID">urn:uuid:#{metadata[:id]}</dc:identifier>
    <dc:title>#{metadata[:title]}</dc:title>
    <dc:creator opf:role="aut">#{metadata[:author]}</dc:creator>
    <dc:language>#{metadata[:language]}</dc:language>
    <meta name="#{metadata[:generator_name]}" content="#{metadata[:generator_version]}" />
  </metadata>
  <manifest>#{manifest}
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
		
		ncxData = MakeNcx(
			:bookArray => bookArray,
			:metadata => metadata, 
		)
		puts "\n=================================== NCX =================================="
		puts ncxData
		
		opfData = MakeOpf(
			:bookArray => bookArray,
			:metadata => metadata, 
		)
		puts "\n=================================== OPF =================================="
		puts opfData
		
		File.open('/home/andrey/Desktop/ncx.xml','w') { |file| file.write(ncxData) }
		File.open('/home/andrey/Desktop/opf.xml','w') { |file| file.write(opfData) }
	end


end


start_time = Time.now


book = Book.new(
	:metadata => {
		:title => 'test book',
		:author => 'разные авторы',
		:language => 'ru',
	},
	:source => [
		'https://ru.wikipedia.org/wiki/Самооценка',
	],
	:options => {
		:depth => 5,
		:total_pages => 15,
		:pages_per_level =>3,
		
		:threads => 1,
		:links_per_level => 5,
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

#book.prepare()

#book.create('test-book.epub')


puts "", "время выполнения: #{Time.now - start_time}"
