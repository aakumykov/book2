
plugin:// uri : www/load : page

rules = {
	'новостная страница' => 'plugin:// page:news_page:uri -> uri:www/load:page',

URI => загрузить страницу новости ->
-> страница новости ->
-> обработать соотв. фильтром ->
-> загрузить страницу с комментариями ->
-> обработать фильтром => PAGE

фильтр: single_news_page.rb

'http://www.opennet.ru/opennews/art.shtml?num=42926' => 'piece_of_news.rb'

class PieceOfNews < PluginSkel
	def work(arg)
		comment_uri = 'http://www.opennet.ru/openforum/vsluhforumID3/104629.html#1'
		comments_page = Book.plugin(
			:name => 'www/load',
			:data => comment_uri,
		)
	end
	