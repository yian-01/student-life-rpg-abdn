// Original local synthesis. Activation only follows an explicit sound switch.
(()=>{let context,source,gain,enabled=false;
window.keyuGardenAudio=(on,speed,rustle)=>{
 if(on&&!context){
  const Audio=window.AudioContext||window.webkitAudioContext;if(!Audio)throw Error('Audio unavailable');
  context=new Audio();const buffer=context.createBuffer(1,context.sampleRate*2,context.sampleRate),data=buffer.getChannelData(0);
  let previous=0;for(let i=0;i<data.length;i++){previous=(previous+(Math.random()*2-1)*.025)/1.025;data[i]=previous*3.5;}
  source=context.createBufferSource();source.buffer=buffer;source.loop=true;const filter=context.createBiquadFilter();filter.type='lowpass';filter.frequency.value=850;
  gain=context.createGain();gain.gain.value=0;source.connect(filter);filter.connect(gain);gain.connect(context.destination);source.start();
 }
 enabled=on;if(!context)return;if(on&&context.state==='suspended')context.resume();
 gain.gain.setTargetAtTime(on&&!document.hidden?Math.abs(speed)*.07:0,context.currentTime,.15);
 if(on&&rustle){const buffer=context.createBuffer(1,Math.round(context.sampleRate*.24),context.sampleRate),data=buffer.getChannelData(0);
  for(let i=0;i<data.length;i++)data[i]=(Math.random()*2-1)*Math.pow(1-i/data.length,2);
  const node=context.createBufferSource(),level=context.createGain(),filter=context.createBiquadFilter();node.buffer=buffer;filter.type='bandpass';filter.frequency.value=1800;level.gain.value=.05;
  node.connect(filter);filter.connect(level);level.connect(context.destination);node.start();node.onended=()=>{node.disconnect();filter.disconnect();level.disconnect();};
 }
};
document.addEventListener('visibilitychange',()=>{if(context&&document.hidden)gain.gain.setTargetAtTime(0,context.currentTime,.05);});
window.addEventListener('pagehide',()=>{if(context)window.keyuGardenAudio(false,0,false);});
})();
