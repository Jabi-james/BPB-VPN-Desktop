import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:material_symbols_icons/symbols.dart';
import 'v2ray_store.dart';

class V2rayManagerPage extends StatefulWidget {
 const V2rayManagerPage({super.key});
 @override State<V2rayManagerPage> createState()=>_V2rayManagerPageState();
}
class _V2rayManagerPageState extends State<V2rayManagerPage> with SingleTickerProviderStateMixin {
 late final tabs=TabController(length:3,vsync:this);
 List<V2raySubscription> subs=[]; List<V2rayProfile> profiles=[];
 String? selected; bool loading=true,updating=false;
 final remote=TextEditingController(text:'1.1.1.1'), local=TextEditingController(text:'localhost');
 V2raySubscription? get active { for(final s in subs){if(s.id==selected)return s;} return null; }
 @override void initState(){super.initState();load();}
 @override void dispose(){tabs.dispose();remote.dispose();local.dispose();super.dispose();}
 Future<void> load() async {
  final s=await V2rayStore.subscriptions(), p=await V2rayStore.profiles(), d=await V2rayStore.dns();
  if(!mounted)return; setState((){subs=s;profiles=p;selected=s.isEmpty?null:s.first.id;remote.text=d['remote']!;local.text=d['local']!;loading=false;});
 }
 Future<void> persist() async {await V2rayStore.saveSubscriptions(subs);await V2rayStore.saveProfiles(profiles);}
 void note(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
 Future<bool> confirm(String title,String message) async => await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(title),content:Text(message),actions:[
  TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),
  FilledButton(style:FilledButton.styleFrom(backgroundColor:const Color(0xFFD94B4B)),onPressed:()=>Navigator.pop(c,true),child:const Text('Delete'))]))==true;
 Future<void> editSub([V2raySubscription? old]) async {
  final n=TextEditingController(text:old?.name??''),u=TextEditingController(text:old?.url??'');
  final v=await showDialog<({String n,String u})>(context:context,builder:(c)=>AlertDialog(title:Text(old==null?'Add subscription':'Edit subscription'),
   content:SizedBox(width:440,child:Column(mainAxisSize:MainAxisSize.min,children:[
    TextField(controller:n,decoration:const InputDecoration(labelText:'Remark / Name')),
    const SizedBox(height:12),TextField(controller:u,decoration:const InputDecoration(labelText:'Subscription URL'),keyboardType:TextInputType.url),
   ])),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),
    FilledButton(onPressed:()=>n.text.trim().isEmpty||u.text.trim().isEmpty?null:Navigator.pop(c,(n:n.text.trim(),u:u.text.trim())),child:const Text('Save'))]));
  n.dispose();u.dispose();if(v==null||!mounted)return;
  setState((){if(old==null){final id=DateTime.now().microsecondsSinceEpoch.toString();subs.add(V2raySubscription(id:id,name:v.n,url:v.u));selected=id;}
   else{subs=subs.map((s)=>s.id==old.id?V2raySubscription(id:s.id,name:v.n,url:v.u):s).toList();}});
  await V2rayStore.saveSubscriptions(subs);
 }
 Future<void> deleteSub(V2raySubscription s) async {
  if(!await confirm('Delete subscription?','Delete ${s.name} and its imported configurations?'))return;
  setState((){subs.removeWhere((x)=>x.id==s.id);profiles.removeWhere((p)=>p.subscriptionId==s.id);selected=subs.isEmpty?null:subs.first.id;});await persist();
 }
 Future<void> updateSub([V2raySubscription? item]) async {
  final s=item??active;if(s==null){note('Add a subscription first.');return;}
  setState(()=>updating=true);
  try{
   final r=await http.get(Uri.parse(s.url)).timeout(const Duration(seconds:25));
   if(r.statusCode<200||r.statusCode>=300)throw Exception('HTTP ${r.statusCode}');
   final parsed=V2rayStore.parseLinks(r.body,subscriptionId:s.id);
   if(parsed.isEmpty)throw Exception('No supported VLESS, VMess, Trojan or Shadowsocks links found.');
   setState((){profiles.removeWhere((p)=>p.subscriptionId==s.id);profiles.addAll(parsed);});
   await persist();note('Updated ${s.name}: ${parsed.length} configurations.');
  }catch(e){note('Update failed: $e. Browser CORS policy may block this subscription URL. Existing configs were kept.');}
  finally{if(mounted)setState(()=>updating=false);}
 }
 Future<void> importClipboard() async {
  final raw=(await Clipboard.getData(Clipboard.kTextPlain))?.text??'';
  final list=V2rayStore.parseLinks(raw);
  if(list.isEmpty){note('No supported V2Ray links or base64 subscription found in clipboard.');return;}
  setState(()=>profiles.addAll(list));await V2rayStore.saveProfiles(profiles);note('${list.length} config(s) imported.');
 }
 Future<void> editProfile(V2rayProfile p) async {
  final n=TextEditingController(text:p.name),r=TextEditingController(text:p.raw);
  final v=await showDialog<({String n,String r})>(context:context,builder:(c)=>AlertDialog(title:const Text('Edit configuration'),
   content:SizedBox(width:480,child:Column(mainAxisSize:MainAxisSize.min,children:[
    TextField(controller:n,decoration:const InputDecoration(labelText:'Remark')),
    const SizedBox(height:12),TextField(controller:r,minLines:3,maxLines:6,decoration:const InputDecoration(labelText:'Share link')),
   ])),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),
    FilledButton(onPressed:()=>Navigator.pop(c,(n:n.text.trim(),r:r.text.trim())),child:const Text('Save'))]));
  n.dispose();r.dispose();if(v==null||v.n.isEmpty)return;
  final parsed=V2rayStore.parseLinks(v.r,subscriptionId:p.subscriptionId);if(parsed.isEmpty){note('Invalid or unsupported share link.');return;}
  final q=parsed.first;setState(()=>profiles=profiles.map((x)=>x.id==p.id?V2rayProfile(id:x.id,name:v.n,address:q.address,protocol:q.protocol,raw:v.r,subscriptionId:x.subscriptionId):x).toList());
  await V2rayStore.saveProfiles(profiles);
 }
 Future<void> deleteProfile(V2rayProfile p) async {if(!await confirm('Delete configuration?','Delete ${p.name}?'))return;setState(()=>profiles.removeWhere((x)=>x.id==p.id));await V2rayStore.saveProfiles(profiles);}
 @override Widget build(BuildContext context){
  final theme=Theme.of(context);final visible=profiles.where((p)=>p.subscriptionId.isEmpty||selected==null||p.subscriptionId==selected).toList();
  return Scaffold(appBar:AppBar(title:const Row(children:[Icon(Symbols.hub_rounded,color:Color(0xFFFFA34D)),SizedBox(width:10),Text('V2Ray',style:TextStyle(fontWeight:FontWeight.w800))])),
   body:SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(18,8,18,18),child:Column(children:[
    Align(alignment:Alignment.centerLeft,child:Text('Connection settings',style:theme.textTheme.titleSmall)),
    TabBar(controller:tabs,tabs:const[Tab(text:'Subscriptions'),Tab(text:'Edit Configs'),Tab(text:'DNS')]),
    const SizedBox(height:12),Expanded(child:loading?const Center(child:CircularProgressIndicator()):TabBarView(controller:tabs,children:[
     subscriptionTab(theme),configTab(theme,visible),dnsTab(theme)
    ]))
   ]))));
 }
 Widget subscriptionTab(ThemeData t)=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
  Row(children:[Text('Subscription groups',style:t.textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800)),const Spacer(),
   IconButton.filledTonal(onPressed:()=>editSub(),icon:const Icon(Icons.add),tooltip:'Add'),
   IconButton.filledTonal(onPressed:active==null?null:()=>editSub(active),icon:const Icon(Icons.edit_outlined),tooltip:'Edit'),
   IconButton(onPressed:active==null?null:()=>deleteSub(active!),icon:const Icon(Icons.delete_outline),tooltip:'Delete')]),
  Expanded(child:subs.isEmpty?empty('No subscriptions','Add a subscription URL, then update it to import server profiles.'):ListView.separated(itemCount:subs.length,separatorBuilder:(_,_)=>const SizedBox(height:6),itemBuilder:(_,i){
   final s=subs[i];return Card(child:ListTile(selected:s.id==selected,onTap:()=>setState(()=>selected=s.id),leading:const Icon(Icons.rss_feed_rounded),
    title:Text(s.name),subtitle:Text(s.url,maxLines:1,overflow:TextOverflow.ellipsis),
    trailing:IconButton(onPressed:updating?null:()=>updateSub(s),icon:const Icon(Icons.refresh_rounded),tooltip:'Update subscription')));
  })),
  FilledButton.icon(onPressed:updating||active==null?null:()=>updateSub(),icon:const Icon(Icons.sync),label:Text(updating?'Updating…':'Update selected subscription')),
  const SizedBox(height:7),OutlinedButton.icon(onPressed:importClipboard,icon:const Icon(Icons.content_paste),label:const Text('Import from clipboard')),
  const SizedBox(height:7),Text('Browser CORS restrictions may block some subscription hosts. Failed updates are reported; existing configurations are retained.',style:t.textTheme.bodySmall)
 ]);
 Widget configTab(ThemeData t,List<V2rayProfile> list)=>Column(children:[
  Row(children:[Text('Edit Configs',style:t.textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800)),const Spacer(),
   DropdownButton<String?>(value:selected,hint:const Text('All groups'),items:[const DropdownMenuItem<String?>(value:null,child:Text('All groups')),...subs.map((s)=>DropdownMenuItem<String?>(value:s.id,child:Text(s.name)))],
    onChanged:(v)=>setState(()=>selected=v))]),
  Expanded(child:list.isEmpty?empty('No configurations','Import links from clipboard or select and update a subscription.'):ListView.separated(itemCount:list.length,separatorBuilder:(_,_)=>const SizedBox(height:7),itemBuilder:(_,i){
   final p=list[i];return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[Icon(Icons.dns_rounded,color:t.colorScheme.primary),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Text(p.name,maxLines:1,overflow:TextOverflow.ellipsis,style:t.textTheme.titleSmall?.copyWith(fontWeight:FontWeight.w800)),
     Text('${p.protocol} · ${p.address}',maxLines:1,overflow:TextOverflow.ellipsis,style:t.textTheme.bodySmall)]))]),
    Row(mainAxisAlignment:MainAxisAlignment.end,children:[TextButton.icon(onPressed:()=>deleteProfile(p),icon:const Icon(Icons.delete_outline),label:const Text('Delete')),
     const SizedBox(width:8),FilledButton.tonalIcon(onPressed:()=>editProfile(p),icon:const Icon(Icons.edit_outlined),label:const Text('Edit'))])
   ])));
  }))
 ]);
 Widget dnsTab(ThemeData t)=>ListView(padding:const EdgeInsets.only(top:12),children:[
  Text('DNS settings',style:t.textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800)),
  const SizedBox(height:8),const Text('Saved separately from BPB DNS settings.'),
  const SizedBox(height:18),TextField(controller:remote,decoration:const InputDecoration(labelText:'Remote DNS',hintText:'1.1.1.1')),
  const SizedBox(height:14),TextField(controller:local,decoration:const InputDecoration(labelText:'Local DNS',hintText:'localhost')),
  const SizedBox(height:18),FilledButton.icon(onPressed:()async{await V2rayStore.saveDns(remote.text.trim(),local.text.trim());note('V2Ray DNS settings saved.');},icon:const Icon(Icons.save_outlined),label:const Text('Save DNS settings'))
 ]);
 Widget empty(String title,String body)=>Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
  Icon(Icons.dns_outlined,size:42,color:Theme.of(context).colorScheme.onSurfaceVariant),const SizedBox(height:12),
  Text(title,style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800)),
  const SizedBox(height:6),Text(body,textAlign:TextAlign.center)
 ])));
}
