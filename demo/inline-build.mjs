import fs from 'node:fs/promises';
const root=new URL('./',import.meta.url), dir=new URL('build/',root);
let html=await fs.readFile(new URL('dev.html',dir),'utf8');
const script=html.match(/<script[^>]+src="([^"]+)"[^>]*><\/script>/);
const css=html.match(/<link[^>]+href="([^"]+\.css)"[^>]*>/);
if(css){const text=await fs.readFile(new URL(css[1],dir),'utf8');html=html.replace(css[0],()=>'<style>'+text+'</style>');}
const js=await fs.readFile(new URL(script[1],dir),'utf8');
html=html.replace(script[0],()=>'<script type="module">'+js.replaceAll('</script','<\\/script')+'</script>');
await fs.writeFile(new URL('index.html',root),html);
console.log('Built self-contained demo/index.html');
