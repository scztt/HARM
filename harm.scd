

// Read and process file

s.options.device = ServerOptions.devices[12];

(
var audio, freq, period, buffer, crossingBuffer, synth, pitchBuffer, pitches;
var lastSample=0, lastZeroCrossing=0;

var soundfile = SoundFile.new;
var overshoot, env, path, baseFreq;

//path = "/Users/fsc/Documents/_sounds/cello/C-string/C-str-7_mono.aif";
~baseFreq = 261;
path = "/Users/fsc/Documents/_sounds/cello/C-string/C-str-7-m-261.aif";
// path = "/Users/fsc/Documents/_sounds/phil-samples/_forHARM/french-horn_F4_very-long_piano_glissando.wav";
// path = "/Users/fsc/Documents/_sounds/phil-samples/_forHARM/french-horn_C3_very-long_pianissimo_normal.wav";
//path = "/Users/fsc/Documents/_sounds/stand/bluett.aiff";
//path = "/Users/fsc/Documents/_sounds/antlers/bear-full.wav";
//path = "/Users/fsc/Documents/_sounds/stand/dolce1.aiff";
//path = "/Users/fsc/Documents/_sounds/cello/scelsi.wav";
//path = "/Users/fsc/Documents/_sounds/playthrough.aiff";
//path = "/Users/fsc/Documents/_sounds/melodica/1.wav";
//path = "/Users/fsc/Desktop/saw.wav";
//path = "/Users/fsc/Desktop/humA1_44_mono.wav";

//Server.default = s = Server.internal.boot;
s.wait;
soundfile.openRead( path );

~audio = audio = Signal.newClear( soundfile.numFrames.postln );
soundfile.readData( audio );
soundfile.close();
//~buffer.play;
~rms = {
	| sig, windowSize = 64 |
	var pos, sum=0, result;
	result = sig.copy();
	sum = sig[0..windowSize].sum({ |v| v * v });

	Range(windowSize, sig.size - windowSize).do({
		| i |
		sum = sum + (sig.foldAt(i)).pow(2)
		- (sig.foldAt(i - windowSize).pow(2));
		result[i - (windowSize / 2)] = sum.pow(0.5);
	});
	result;
};
~audiorms = ~rms.(~audio, 8);

~zeroCrossings = List.new;


fork {
	var currentPitch, currentPeriod, lastCrossing,
	currentSample, nextSample, nextSampleMod, aValue, bValue, done,
	searchStart, searchEnd, maxIndex, plotter;

	~buffer = buffer = Buffer.read( s, path );
	pitchBuffer = Buffer.alloc( s, soundfile.numFrames/64 + 100 );
	env = Buffer.loadCollection( s, FloatArray.fill( 1000, 1 ) );
	s.sync;
	n = {
		var sig, hasFreq, freq;
		sig = PlayBuf.ar( 1, buffer.bufnum, doneAction:2 );
		sig = HPF.ar( LPF.ar( sig, 2000), 60 );
		//#freq, hasFreq = Pitch.kr( sig, 800, 100, 1400, execFreq: 200, median:14, peakThreshold:0.75, downSample:1 );
		#freq, hasFreq = Tartini.kr(sig, n:2048 , k:2048, overlap:1024, smallCutoff:0.7);
		freq = Gate.kr( freq, hasFreq > 0.45 );
		RecordBuf.kr( Lag3.kr(freq, 0.01), pitchBuffer.bufnum );
	}.play;
	(soundfile.numFrames/soundfile.sampleRate).wait;
	{ pitchBuffer.plot( "pitch", minval: 40, maxval:1600 ) }.defer;
	pitchBuffer.getToFloatArray( wait:0.1, timeout:30, action:{ | array | pitches = array; [ soundfile.numFrames, pitches.size].postln });

	currentSample = 0;
	lastCrossing = 0;
	audio.size.postln;

	{ plotter = ([0 ! 512, 0 ! 512]).plot }.defer;
	0.5.wait;
	while({ currentSample < audio.size }, {
		currentPitch = pitches[currentSample / 64];

		if( currentPitch > 20, {
			currentPeriod = min(~buffer.sampleRate / currentPitch, ~buffer.sampleRate).round(1);
			nextSample = currentSample + currentPeriod;
			searchStart = (nextSample - (currentPeriod / 4)).asInteger;
			searchEnd = (nextSample + (currentPeriod / 4)).asInteger;

			maxIndex = ~audiorms.asArray[searchStart..searchEnd].maxIndex;

			{
				plotter.setValue([
					~audio.asArray[searchStart..searchEnd],
					~audiorms.asArray[searchStart..searchEnd]
				]);
			}.defer;
			0.001.wait;

			if (maxIndex.isNil) {
				maxIndex = nextSample ?? 0;
				"No max found: %".postf(~audiorms.asArray[searchStart..searchEnd]);
			};
			maxIndex = searchStart + maxIndex;

			"\t%:% [%..%] -> %\n".postf(currentSample, currentPeriod, searchStart, searchEnd, maxIndex - nextSample);
			~zeroCrossings.add(maxIndex);
			//~zeroCrossings.add(nextSample);
			currentSample = maxIndex;
		}, {
			currentSample = currentSample + 1;
		});
	});
	"DONE".postln;
}
)


~splits = FloatArray.newClear(~audio.size);
~zeroCrossings.do { |i|
	~splits[i] = 1;
};

~plotLoc = {
	|l|
	[
		~splits[~zeroCrossings[l].asInteger..~zeroCrossings[l + 20].asInteger],
		~audio[~zeroCrossings[l].asInteger..~zeroCrossings[l + 20].asInteger],
		~audiorms[~zeroCrossings[l].asInteger..~zeroCrossings[l + 20].asInteger],
	].plot;
};
~plotLoc.(2200);

(
~crossingBuffer = Buffer.loadCollection(s, ~zeroCrossings.asArray);
~envsize = 1024;
~transition = ~envsize * 0.25;

~envcoll = ~envsize.collect({
	| i |
	case
	{ i < ~transition }
	{ cos(pi * i / ~transition).neg + 1 / 2 }

	{ i > (~envsize - ~transition) }
	{ cos(pi * (~envsize - i) / ~transition).neg + 1 / 2 }
	{ true }
	{ 1};
});
~envcoll.plot;
~env = Buffer.loadCollection(s, ~envcoll);
//~env.loadCollection( ~envcoll );
)

s.sync;
buffer.plot;



(
~harmbase = {
	arg amp=1, pos, jump = 1, nextJump = 1, wavelength = 1, grainDur = 2, resFreq = 1, resAmt=10, resBump=0, freq=440, pan=0, crossingBuffer, soundBuffer, envBuffer;

	var centerPos, centerPosA, centerPosB, centerPosMix,
	nextCenterPosA, nextCenterPosB,
	centerA, centerB, nextCenterA, nextCenterB,
	dur, durA, durB, startA, startB, nextStartA, nextStartB,
	trig, trigStartA, trigStartB, trigNextStartA, trigNextStartB, trigDurA, trigDurB,
	sig, crossingBufferSamples, soundBufferSamples;

	soundBufferSamples = BufSamples.ir(soundBuffer);
	crossingBufferSamples = BufSamples.ir(crossingBuffer);

	resFreq = freq * resFreq;
	wavelength = LFNoise2.kr(0.05, 0.05, wavelength);
	centerPos = pos * crossingBufferSamples;

	centerPosA 		= Select.kr(centerPos.floor % 2, [centerPos.floor + jump, centerPos.floor]);
	centerPosB 		= Select.kr(centerPos.floor % 2, [centerPos.floor, centerPos.floor + jump]);
	centerPosMix 	= Select.kr(centerPos.floor % 2, [1 - (centerPos - centerPosB), centerPos - centerPosA]);

	// nextCenterPosA 	= centerPosA + (1 - env * 6).round(1);
	// nextCenterPosB 	= centerPosB + (1 - env * 6).round(1);
	nextCenterPosA 	= centerPosA + nextJump;
	nextCenterPosB 	= centerPosB + nextJump;

	centerA 		= { Dbufrd(crossingBuffer, centerPosA % crossingBufferSamples, 1) };
	centerB			= { Dbufrd(crossingBuffer, centerPosB % crossingBufferSamples, 1) };
	nextCenterA		= { Dbufrd(crossingBuffer, nextCenterPosA % crossingBufferSamples, 1) };
	nextCenterB		= { Dbufrd(crossingBuffer, nextCenterPosB % crossingBufferSamples, 1) };
	durA = { ((nextCenterA - centerA) / SampleRate.ir).max(0.0000000001).min(1) / wavelength };
	durB = { ((nextCenterB - centerB) / SampleRate.ir).max(0.0000000001).min(1) / wavelength };

	startA = centerA - (durA / 2);
	startB = centerB - (durB / 2);
	nextStartA = nextCenterA - (durA / 2);
	nextStartB = nextCenterB - (durB / 2);

	dur = freq.reciprocal;
	#trig, trigStartA, trigStartB, trigNextStartA, trigNextStartB, trigDurA, trigDurB =
		TDuty.ar(dur, 0, [1, centerA, centerB, nextCenterA, nextCenterB, durA, durB]);

	// Out.kr(0, [ centerPosMix, centerPosA, centerPosB,
	// 	Gate.ar( trigDurA, trigDurA),
	// 	Gate.ar( trigStartA / BufSamples.kr(~buffer.bufnum), trigStartA / BufSamples.kr(~buffer.bufnum)),
	// 	Gate.ar( trigDurB, trigDurB),
	// 	Gate.ar( trigStartB / BufSamples.kr(~buffer.bufnum) , trigStartB / BufSamples.kr(~buffer.bufnum))
	// ]);

	sig = [
		XFade2.ar(
			BufGrainB.ar( trig,
				dur: trigDurA * grainDur,
				sndbuf: soundBuffer,
				rate: resFreq.explin(50, 4000, 0.25, 2.5),
				pos: trigStartA / soundBufferSamples,
				envbuf: envBuffer,
				interp: 4),
			DC.ar(0),
			(centerPosMix * 2 - 1)
		),
		XFade2.ar(
			DC.ar(0),
			BufGrainB.ar( trig,
				dur: trigDurB * grainDur,
				sndbuf: soundBuffer,
				rate: resFreq.explin(50, 4000, 0.25, 2.5),
				pos: trigStartB / soundBufferSamples,
				envbuf: envBuffer,
				interp: 4),
			(centerPosMix * 2 - 1)
		)
	].sum;
	sig = sig * amp;
	sig = sig + Klank.ar(`[
		[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14],
		[-75, -83, -97, -97, -90, -95, -99, -108, -111, -111, -111, -96, -112, -114].dbamp * 10,
		(0.1 / (1..14))
	], sig, freqscale: resFreq, decayscale:resAmt);
	sig = LeakDC.ar(sig);
	sig = Pan2.ar(sig, pan);
};

DistCurve(\krsh,
	[-1, 0, 1],
	Env([-1, -0.8, -0.5, -0.8, 0.8, 0.5, 0.8, 1.0], curve:\hold)
);

SynthDef(\longSineHARM, {
	arg out, amp = 1, dur = 20, bowFreq=1.5, periodNum;
	var env, sig, jump;
	env = amp * EnvGen.kr(Env.sine(dur * 1.4), doneAction:2);
	jump = LFNoise2.ar(0.2, 1, 4 + env);
	sig = SynthDef.wrap(~harmbase, prependArgs: [
		env,
		LFNoise2.kr(LFNoise2.kr(3, bowFreq / 2, bowFreq), 0.1, 0.2),
		jump
	]);
	sig = sig + MoogLadder.ar(DistCurve(\krsh).ar(sig, MouseX.kr(0, 1), MouseY.kr(0, 48), MouseY.kr(0, -48)), 8640, 0.2);
	sig = LeakDC.ar(sig);
	Out.ar(out, sig);
}).addReplace;

SynthDef(\strikeHARM, {
	arg out=0, amp = 1, dur = 20, bowFreq=1.5, startPos=0.9, endPos=0.9, gate = 1;
	var env, sig;
	env = amp * EnvGen.kr(Env.adsr(1.1, 1.1, 0.01, 20), gate:gate, timeScale: dur, doneAction:2);
	sig = SynthDef.wrap(~harmbase, prependArgs: [
		env,
		LFNoise2.kr(LFNoise2.kr(3, bowFreq / 2, bowFreq), 0.1, Line.kr(startPos, endPos, dur))
	]);
	Out.ar(out, sig);
}).add;

SynthDef(\postHARM, {
	| in, out, wetAmp |
	var sig, wetSig;
	sig = In.ar(in, 2);
	wetSig = Rotate2.ar(sig[0], sig[1], SinOsc.ar(0.0221)).collect({
		|s|
		Mix.ar(CombC.ar(s, 5, [0.1 + rand(-0.04, 0.04), 0.5 + rand(-0.04, 0.04), 2.3 + rand(-0.04, 0.04), 4.5 + rand(-0.04, 0.04)], 8));
	});
	wetSig = FreeVerb.ar(wetSig, room:2.9);
	Out.ar(out, sig + (wetAmp * wetSig));
}).addReplace;

)

(
Pdef(\test, Pbind(
	\freq, Pseq(([-3, 1, 4, 8, 13] + 68).midicps, inf),
	\freq, Pseq(([-4, 1, 4, 8, 11] + 68).midicps, inf),
	\freq, Pseq(([-4, 1, 4, 9, 11] + 68).midicps, inf),
	\freq, Pseq(([-3, 2, 4, 9, 11] + 68).midicps, inf),
	\freq, Pseq(([-4, 2, 4, 9, 11] + 68).midicps, inf),
	\freq, Pseq(([-6, 2, 4, 9, 14] + 68).midicps, inf),
	\freq, Pseq(([-8, 2, 4, 6, 11] + 68).midicps, inf),
	\freq, Pseq(([-8, -2, 3, 6, 10] + 68).midicps, inf),
	\dur, 0.1
)).play;
)

(
Pdef(\pat1, Pbind(
	\instrument, \longSineHARM,
	\dur, Pseq([24], inf),
	\amp, 1,
	\freq, Pseq([
		([-3 + [0, -12, -24], 1, 4, 8, 13].flatten + 48).midicps,
		([-4 + [0, -12, -24], 1, 4, 8, 11].flatten + 48).midicps,
		([-4 + [0, -12, -24], 1, 4, 9, 11].flatten + 48).midicps,
		([-3 + [0, -12, -24], 2, 4, 9, 11].flatten + 48).midicps,
		([-4 + [0, -12, -24], 2, 4, 9, 11].flatten + 48).midicps,
		([-6 + [0, -12, -24], 2, 4, 9, 14].flatten + 48).midicps,
		([-8 + [0, -12, -24], 2, 4, 6, 11].flatten + 48).midicps,
		([-8 + [0, -12, -24], -2, 3, 6, 10].flatten + 48).midicps,
		([-6-12, -6, 2, 4.1, 7, 7.1, 7.064, 12, 12.05] + 68).midicps,
		([-6-12, -6, 1, 1.1, 7, 7.1, 7.064, 15, 15.05] + 68).midicps
		([-14-12, -4, 0, 0.1, 8, 8.1, 8.064, 14, 14.05] + 48).midicps
	], inf) ,
//	\freq, ([-3-12, -3, 2, 4.1, 8, 8.1, 8.064, 14, 14.05] + 68).midicps,
	\pan, { rand(-0.4, 0.4) },
	\resFreq, 1 / 8,
	\jump, 4,
	\nextJump, 4,
	\grainDur, 2,
	\bowFreq, 0.12,
	\startPos, 0.1,
	\endPos, 0.9,
	\out, 10,
	\crossingBuffer, ~crossingBuffer.bufnum,
	\soundBuffer, ~buffer.bufnum,
	\envBuffer, ~env.bufnum,
)).play
)

(
Pdef(\pat2, Pbind(
	\freq, Pseq([
		([-4 + [0, -12, -24], 1, 4, 8, 11, 8 + 12].flatten + 38).midicps,
		([-4 + [0, -12, -24], 1, 4, 4 + 12, 6 + 12].flatten + 28).midicps.postln,
		([-3 + [0, -12, -24], 1, 4, 8, 13].flatten + 28).midicps,
	], inf)
) <> Pdef(\pat1)).play;
)

(
(
instrument: \postHARM,
in: 10,
out: 0
).play;

(.
instrument: \longSineHARM,
out: 10,
dur: 30,
amp: 1,
// 40 -> 42 -> 40 -> 38 etc.
freq: ([-3 + [0, 12, 24, 36, 43.3]].flatten + 48 + { 0.3.rand }).value.midicps,
pan: { rand(-0.9, 0.9) },
resFreq: 1 / 8,
jump: 4,
nextJump: 2,
grainDur: 2,
bowFreq: 0.5,
crossingBuffer: ~crossingBuffer.bufnum,
soundBuffer: ~buffer.bufnum,
envBuffer: ~env.bufnum,
).play
);

(
(
instrument: \postHARM,
in: 10,
out: 0
).play;

(
instrument: \strikeHARM,
out: 10,
dur: 10,
amp: 1,
freq: ([-3 + [0, 0.1, 0.21, 3, 3.013]].flatten + 25 + { 0.3.rand }).value.midicps,
pan: { rand(-0.9, 0.9) },
resFreq: 1.0,
jump: 8,
nextJump: 12,
grainDur: 12,
bowFreq: 0.6,
crossingBuffer: ~crossingBuffer.bufnum,
soundBuffer: ~buffer.bufnum,
envBuffer: ~env.bufnum,
).play
)


~cap = AudioCapture("/Users/fsc/Desktop/SC_CLEAN/HARM/_capture");
~cap.track = "harm";
~cap.start
~cap.stop
