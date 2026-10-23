import {test} from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const module=await build({stdin:{contents:"export {SurfaceTimeline,answerBlocks,blockKey} from './vendor/intelligent-ui/surfaces'; export {UIStream} from './vendor/intelligent-ui/stream'; export {compileUI,evaluate} from './vendor/intelligent-ui/runtime'",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const {SurfaceTimeline,blockKey,UIStream,compileUI,evaluate}=await import('data:text/javascript;base64,'+Buffer.from(module.outputFiles[0].text).toString('base64'));
const source=[{op:'begin',version:2,surfaceId:'plan',title:'桌面计划'},{op:'state',key:'count',initial:2},{op:'state',key:'tab',initial:'one'},{op:'node',node:{id:'quantity',type:'stepper',label:'人数',bind:'count',min:1,max:20}},{op:'node',node:{id:'tabs',type:'tabs',bind:'tab'}},{op:'node',parent:'tabs',node:{id:'one',type:'section',label:'概览'}},{op:'node',parent:'one',node:{id:'total',type:'metric',label:'总额',value:{op:'mul',args:[{state:'count'},12]}}},{op:'node',parent:'tabs',node:{id:'two',type:'section',label:'详情',value:'内容'}},{op:'commit'}].map(v=>JSON.stringify(v,null,2)).join('\n');
const msg=(id,text,streaming=false,scope='test')=>({id,identity:id,scope,text:'```intelligent-ui\n'+text+'\n```',streaming});
test('desktop multiline JSON events, tabs and dynamic expressions',()=>{
  const result=new UIStream().update(source,false); assert.equal(result.error,'');assert.equal(result.doc.body[1].children.length,2);assert.equal(evaluate(result.doc.body[1].children[0].children[0].value,{count:3}),36);
});
test('cross-turn patches commit atomically and reject stale versions',()=>{
  const update=[{op:'begin',version:2,surfaceId:'plan',mode:'patch',baseRevision:1},{op:'node',node:{id:'total',type:'metric',label:'更新总额',value:99}},{op:'commit'}].map(JSON.stringify).join('\n');
  const timeline=new SurfaceTimeline(); let blocks=timeline.build([msg('a',source),msg('b',update)]);let surface=blocks.get(blockKey('a','ui-0')).surface;assert.equal(surface.versions.length,2);assert.equal(surface.versions[1].doc.body[1].children[0].children[0].value,99);
  blocks=timeline.build([msg('a',source),msg('b',update),msg('c',update)]);assert.match(blocks.get(blockKey('c','ui-0')).error,/当前界面为第 2 版/);assert.equal(blocks.get(blockKey('a','ui-0')).surface.versions.length,2);
  blocks=timeline.build([msg('a',source),msg('b',update,true)]);assert.equal(blocks.get(blockKey('a','ui-0')).surface.versions.length,1);
  blocks=timeline.build([msg('a',source),msg('b',update,false,'other')]);assert.match(blocks.get(blockKey('b','ui-0')).error,/找不到/);
});
test('image, diagram and isolated app nodes validate; invalid URLs and attributes fail',()=>{
  const doc={version:1,title:'Components',state:{part:'a'},body:[{id:'image',type:'image',src:'https://example.test/image.png'},{id:'drawing',type:'diagram',bind:'part',width:100,height:100,parts:[{id:'a',label:'部件',description:'描述'}],shapes:[{type:'circle',x:50,y:50,r:20,part:'a'}]},{id:'app',type:'app',code:'ui.render({version:1,title:"OK",state:{},body:[]})'}]};
  assert.equal(compileUI(JSON.stringify(doc)).body.length,3);
  for(const src of ['javascript:alert(1)','file:///etc/passwd','data:image/svg+xml,<svg/>'])assert.throws(()=>compileUI(JSON.stringify({...doc,body:[{id:'img',type:'image',src}]})));
});
