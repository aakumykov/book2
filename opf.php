<?php
//header("Content-Type: text/html; charset=UTF-8",true);
////include_once('debug.php');
////include_once('exception.php');

class Opf extends Debug
{
	private $metadata;
	private $tocArray;

	protected $manifest;
	protected $spine;
	protected $guide;	
	
	function __construct()
	{
		$this->debug(__METHOD__);
	}
	
	function makeManifest($tocArray)
	{
		if(! is_array($tocArray)) throw new ParamException("arg must be an array");
		
		$data = "";
		
		// tocArray - простой массив, его подмассивы содержат пары ключ-значение
		foreach($tocArray as $item)
		{
			$id = md5($item['title']);
			$data .= "\n\t<item href='{$item['file']}' id='{$id}' media-type='application/xhtml+xml' />";
			
			if( isset($item['subitems']) && !empty($item['subitems'])) $data .= $this->makeManifest($item['subitems']);
		}
		
		return $data;
	}

	function makeSpine($tocArray)
	{
		if(! is_array($tocArray)) throw new ParamException("arg must be an array");
		
		$data = "";
		
		// tocArray - простой массив, его подмассивы содержат пары ключ-значение
		foreach($tocArray as $item)
		{
			$id = md5($item['title']);
			$data .= "\n\t<itemref idref='{$id}' />";
			
			if( isset($item['subitems']) && !empty($item['subitems'])) $data .= $this->makeSpine($item['subitems']);
		}
		
		return $data;
	}

	function makeGuide($tocArray)
	{
		if(! is_array($tocArray)) throw new ParamException("arg must be an array");
		
		$data = "";
		
		// tocArray - простой массив, его подмассивы содержат пары ключ-значение
		foreach($tocArray as $item)
		{
			$data .= "\n\t<reference href='{$item['file']}' title='{$item['title']}' type='text' />";
			
			if( isset($item['subitems']) && !empty($item['subitems'])) $data .= $this->makeGuide($item['subitems']);
		}
		
		return $data;
	}

	function generate($metadata,$tocArray)
	{
		$this->metadata = $metadata;
		$this->tocArray = $tocArray;
		
		$this->manifest = $this->makeManifest($this->tocArray);
		$this->spine = $this->makeSpine($this->tocArray);
		$this->guide = $this->makeGuide($this->tocArray);

	$opf = <<<OPF
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:identifier id="BookId" opf:scheme="UUID">urn:uuid:{$this->metadata['id']}</dc:identifier>
    <dc:title>{$this->metadata['title']}</dc:title>
    <dc:creator opf:role="aut">{$this->metadata['author']}</dc:creator>
    <dc:language>{$this->metadata['language']}</dc:language>
    <meta content="{$this->metadata['generator']['version']}" name="{$this->metadata['generator']['name']}" />
  </metadata>
  <manifest>{$this->manifest}
	<item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml" />
  </manifest>
  <spine toc="ncx">{$this->spine}
  </spine>
  <guide>{$this->guide}
  </guide>
</package>

OPF;

		return $opf;
	}
}


//$tocArray = unserialize( file_get_contents("tocArray.txt") );

//$opf = makeOpf( array("title"=>"Opennet.ru"), $tocArray );
//pre($opf);

//$opf = new Opf(array('title'=>'opennet.ru'),$tocArray);
//$data = $opf->generate();
//pre( $data );