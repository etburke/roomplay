// Engine_RoomAnalysis
//
// Norns loads exactly one SuperCollider engine per script, so this engine
// carries both halves of roomplay's audio: line-in analysis (onset/pitch/
// amplitude, reported back to lua as polls) and a small polyphonic voice
// pool for output (noteOn/noteOff, PolyPerc-shaped commands).
//
// Onsets.kr fires a one-sample control-rate trigger. Rather than relying on
// raw SendReply routing, the trigger drives PulseCount.kr into a poll —
// lua diffs the counter between polls to detect onsets. This keeps onset
// delivery inside the documented addPoll/addCommand surface.

Engine_RoomAnalysis : CroneEngine {
	var analysisSynth;
	var voiceGroup;
	var voices;
	var ampBus, freqBus, hasFreqBus, onsetCountBus;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		voices = Array.newClear(128);

		ampBus = Bus.control(context.server, 1);
		freqBus = Bus.control(context.server, 1);
		hasFreqBus = Bus.control(context.server, 1);
		onsetCountBus = Bus.control(context.server, 1);

		SynthDef(\room_analysis, {
			arg in = 0, ampThresh = 0.02, median = 1;
			var sig, amp, freq, hasFreq, chain, onsetTrig, onsetCount;
			// hardware input 0: norns' default line/mic routing
			sig = SoundIn.ar(in);
			amp = Amplitude.kr(sig, attackTime: 0.01, releaseTime: 0.15);
			# freq, hasFreq = Pitch.kr(sig, ampThreshold: ampThresh, median: median, execFreq: 30);
			chain = FFT(LocalBuf(1024), sig);
			onsetTrig = Onsets.kr(chain, 0.5, \wphase);
			onsetCount = PulseCount.kr(onsetTrig);
			Out.kr(ampBus, amp);
			Out.kr(freqBus, freq);
			Out.kr(hasFreqBus, hasFreq);
			Out.kr(onsetCountBus, onsetCount);
		}).add;

		SynthDef(\room_voice, {
			arg out = 0, hz = 220, amp = 0.2, pan = 0, gate = 1,
				release = 0.3, cutoff = 3000;
			var sig, env;
			env = EnvGen.kr(Env.asr(0.003, 1, release), gate, doneAction: 2);
			sig = Saw.ar(hz) + Saw.ar(hz * 1.003);
			sig = MoogFF.ar(sig, cutoff, 1.5);
			sig = Pan2.ar(sig * env * amp * 0.3, pan);
			Out.ar(out, sig);
		}).add;

		context.server.sync;

		voiceGroup = Group.new(context.og);
		analysisSynth = Synth.new(\room_analysis, [\in, 0], context.xg);

		this.addCommand("noteOn", "iff", { arg msg;
			var note = msg[1].asInteger;
			var hz = msg[2];
			var vel = msg[3];
			if (voices[note].notNil) { voices[note].set(\gate, 0) };
			voices[note] = Synth.new(\room_voice,
				[\out, context.out_b.index, \hz, hz, \amp, vel, \gate, 1],
				voiceGroup);
		});

		this.addCommand("noteOff", "i", { arg msg;
			var note = msg[1].asInteger;
			if (voices[note].notNil) {
				voices[note].set(\gate, 0);
				voices[note] = nil;
			};
		});

		this.addCommand("ampThreshold", "f", { arg msg;
			analysisSynth.set(\ampThresh, msg[1]);
		});

		this.addCommand("pitchMedian", "f", { arg msg;
			analysisSynth.set(\median, msg[1].asInteger);
		});

		this.addPoll("amp", { ampBus.getSynchronous });
		this.addPoll("freq", { freqBus.getSynchronous });
		this.addPoll("has_freq", { hasFreqBus.getSynchronous });
		this.addPoll("onset_count", { onsetCountBus.getSynchronous });
	}

	free {
		analysisSynth.free;
		voices.do { |v| if (v.notNil) { v.free } };
		voiceGroup.free;
		ampBus.free;
		freqBus.free;
		hasFreqBus.free;
		onsetCountBus.free;
	}
}
