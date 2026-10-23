import {build} from 'esbuild';
import {readFile,writeFile,copyFile,mkdir} from 'node:fs/promises';
const out='../../ios/Town/IntelligentUIResources';
await mkdir(out,{recursive:true});
await build({entryPoints:['main.tsx'],bundle:true,format:'iife',target:['safari16'],jsx:'automatic',minify:true,define:{'process.env.NODE_ENV':'"production"'},outfile:out+'/iui.js'});
await copyFile('iui-runtime.html',out+'/iui-runtime.html');
await writeFile(out+'/iui.html',`<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src https: data:; frame-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'"><link rel="stylesheet" href="iui.css"></head><body><div id="root"></div><script src="iui.js"></script></body></html>`);
const result=await build({entryPoints:['vendor/intelligent-ui/context.ts'],bundle:true,platform:'node',format:'esm',write:false});
const {intelligentUIContext}=await import('data:text/javascript;base64,'+Buffer.from(result.outputFiles[0].text).toString('base64'));
await writeFile(out+'/iui-context.txt',intelligentUIContext);
let licenses=await readFile('vendor/LICENSE','utf8');
for(const name of ['react','react-dom','scheduler','marked']){
  const path='node_modules/'+name+'/';
  licenses+='\n\n'+name+'\n'+await readFile(path+(name==='marked'?'LICENSE.md':'LICENSE'),'utf8');
}
await writeFile(out+'/iui-LICENSES.txt',licenses);
