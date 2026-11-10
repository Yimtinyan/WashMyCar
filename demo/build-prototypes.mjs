import fs from 'node:fs/promises';
const root=new URL('./prototype-build/',import.meta.url);
let html=await fs.readFile(new URL('prototypes.html',root),'utf8');
for(const m of [...html.matchAll(/<link[^>]+href="([^"]+\.css)"[^>]*>/g)]){
 const css=await fs.readFile(new URL(m[1],root),'utf8');html=html.replace(m[0],()=>'<style>'+css+'</style>');
}
const script=html.match(/<script[^>]+src="([^"]+)"[^>]*><\/script>/);
const js=await fs.readFile(new URL(script[1],root),'utf8');
html=html.replace(script[0],()=>'<script type="module">'+js.replaceAll('</script','<\\/script')+'</script>');
await fs.writeFile(new URL('preview.html',root),html);
console.log('Built independent prototype-build/preview.html; original index.html untouched');
