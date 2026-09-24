#region Using declarations
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Windows.Media;
using NinjaTrader.Cbi;
using NinjaTrader.Gui.Tools;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.DrawingTools;
using NinjaTrader.NinjaScript.Indicators;
#endregion

// =====================================================================
// PriceActionBarByBar — NinjaTrader 8 (NinjaScript / C#) port, Phase 4.
//
// This is a 1:1 architectural port of the MQL5 project under /MQL5 —
// same class boundaries, same IAnalyzer-equivalent contract, same
// separation between analysis and drawing. Only the language and the
// host platform's per-bar update model change.
//
// WHY THIS IS SIMPLER THAN THE MQL5 VERSION IN A FEW PLACES:
//   - NinjaScript calls OnBarUpdate() exactly once per bar, oldest to
//     newest, with Calculate.OnBarClose. MQL5's OnCalculate() can be
//     asked to reprocess a whole history array at once (hence the
//     prev_calculated bookkeeping there) — that bookkeeping simply
//     doesn't exist here.
//   - C# generics let ONE PabRingBuffer<T> class replace the two
//     hand-duplicated circular buffers CBarClassifier/CSwingDetector
//     each carried in MQL5 (which has no generics).
//   - NinjaTrader's ATR() sub-indicator is just an indexable series —
//     no handle/CopyBuffer dance like iATR() in MT5.
//   - Every drawn object here is anchored by DateTime from the start,
//     so the Phase-3 "stale barIndex" bug fixed in the MQL5 version
//     never existed in this port to begin with.
//
// WHY IT'S ONE FILE: NinjaScript indicators are compiled as a single
// file per indicator by the NinjaScript editor. Splitting classes
// across files requires packaging this as a NinjaTrader AddOn instead
// (see README.md "Splitting into an AddOn" for that option) — for a
// drop-in indicator, everything lives here, organized into #region
// blocks that mirror the MQL5 project's file boundaries 1:1.
// =====================================================================

namespace NinjaTrader.NinjaScript.Indicators
{
	#region Shared types (mirrors MQL5/Include/PriceActionBarByBar/PAB_Types.mqh)

	public enum PabBarType { BullTrend, BearTrend, Doji, Inside, Outside }

	public enum PabPullbackType { None, H1, H2, H3Plus, L1, L2, L3Plus }

	public enum PabSignalQuality { NA, Weak, Moderate, Strong }

	public enum PabSwingType { High, Low }

	public enum PabMarketState { TradingRange, BullTrend, BearTrend, Transition }

	public enum PabPatternType { None, HigherHighsLows, LowerHighsLows, DoubleTop, DoubleBottom, Triangle, WedgeRising, WedgeFalling }

	public enum PabAlwaysInState { None, Long, Short }

	public class PabBarInfo
	{
		public DateTime Time;
		public double Open, High, Low, Close;
		public double BodySize, Range, BodyRatio, Clv;
		public bool IsBullish;
		public PabBarType BarType;
		public PabPullbackType PullbackType;
		public int PullbackIndex;
		public PabSignalQuality SignalQuality;
		public bool IsBreakoutBar;
		public bool IsClimax;
	}

	public class PabSwingPoint
	{
		public DateTime Time;
		public double Price;
		public PabSwingType Type;
	}

	public class PabTradingRangeInfo
	{
		public bool Active;
		public double Top, Bottom;
		public DateTime StartTime, EndTime; // stable, unlike a cached bar index
		public double OverlapRatio;
	}

	public class PabPatternInfo
	{
		public PabPatternType Type = PabPatternType.None;
		public DateTime StartTime, EndTime;
		public string Note = "";
	}

	public class PabMeasuredMoveInfo
	{
		public bool Active;
		public bool IsBullish;
		public double Leg1Start, Leg1End, PivotPrice, TargetPrice;
		public DateTime PivotTime;
	}

	#endregion

	#region Generic ring buffer (no MQL5 equivalent needed — C# has generics)

	// One generic O(1) push-front circular buffer, used by both
	// PabBarClassifier and PabSwingDetector. In the MQL5 version this
	// exact logic had to be hand-duplicated in both classes because
	// MQL5 has no generics — see BarClassifier.mqh / SwingDetector.mqh.
	public class PabRingBuffer<T>
	{
		private readonly T[] _buf;
		private readonly int _capacity;
		private int _head;
		private int _count;

		public PabRingBuffer(int capacity)
		{
			_capacity = Math.Max(1, capacity);
			_buf = new T[_capacity];
			_head = 0;
			_count = 0;
		}

		public int Count { get { return _count; } }

		public void PushFront(T item)
		{
			_head = (_head - 1 + _capacity) % _capacity;
			_buf[_head] = item;
			if (_count < _capacity) _count++;
		}

		// i = 0 is the most recently pushed item, increasing i = older.
		public T this[int i]
		{
			get
			{
				if (i < 0 || i >= _count) throw new IndexOutOfRangeException();
				return _buf[(_head + i) % _capacity];
			}
		}

		public void Clear() { _head = 0; _count = 0; Array.Clear(_buf, 0, _capacity); }
	}

	#endregion

	#region Price series abstraction (mirrors passing raw OHLC arrays in MQL5)

	// Decouples the analyzer classes from NinjaScript's Indicator base
	// class, the same way MQL5's classes only ever see plain arrays,
	// never the chart. barsAgo=0 is always "the bar Update() was just
	// called for"; increasing barsAgo = further back in history.
	public interface IPabPriceSeries
	{
		double Open(int barsAgo);
		double High(int barsAgo);
		double Low(int barsAgo);
		double Close(int barsAgo);
		DateTime Time(int barsAgo);
	}

	public class PabNinjaSeriesAdapter : IPabPriceSeries
	{
		private readonly Indicator _host;
		public PabNinjaSeriesAdapter(Indicator host) { _host = host; }
		public double Open(int barsAgo) { return _host.Open[barsAgo]; }
		public double High(int barsAgo) { return _host.High[barsAgo]; }
		public double Low(int barsAgo) { return _host.Low[barsAgo]; }
		public double Close(int barsAgo) { return _host.Close[barsAgo]; }
		public DateTime Time(int barsAgo) { return _host.Time[barsAgo]; }
	}

	#endregion

	#region PabUtils (mirrors PAB_Utils.mqh)

	public static class PabUtils
	{
		public static double BodySize(double o, double c) { return Math.Abs(c - o); }
		public static double BarRange(double h, double l) { return h - l; }

		public static double BodyRatio(double o, double h, double l, double c)
		{
			double range = BarRange(h, l);
			return range <= 0.0 ? 0.0 : BodySize(o, c) / range;
		}

		public static double CloseLocationValue(double h, double l, double c)
		{
			double range = BarRange(h, l);
			return range <= 0.0 ? 0.0 : ((c - l) - (h - c)) / range;
		}

		public static double RangeOverlap(double h1, double l1, double h2, double l2)
		{
			double overlapHigh = Math.Min(h1, h2);
			double overlapLow = Math.Max(l1, l2);
			double overlap = overlapHigh - overlapLow;
			if (overlap <= 0.0) return 0.0;
			double smaller = Math.Min(h1 - l1, h2 - l2);
			return smaller <= 0.0 ? 0.0 : overlap / smaller;
		}

		// Average (High-Low) over 'period' bars starting at barsAgo 'from'
		// (inclusive) going further back, bounded by barsAvailable.
		public static double AverageRange(IPabPriceSeries s, int from, int period, int barsAvailable)
		{
			if (period <= 0) return 0.0;
			double sum = 0.0; int n = 0;
			for (int i = from; i < from + period; i++)
			{
				if (i < 0 || i >= barsAvailable) break;
				sum += s.High(i) - s.Low(i);
				n++;
			}
			return n == 0 ? 0.0 : sum / n;
		}

		public static double Slope(int x1, double y1, int x2, double y2)
		{
			return x1 == x2 ? 0.0 : (y2 - y1) / (double)(x2 - x1);
		}
	}

	#endregion

	#region PabBarClassifier (mirrors BarClassifier.mqh)

	public class PabBarClassifier
	{
		private readonly double _dojiBodyRatio;
		private readonly double _clvFavorableMin;
		private readonly int _breakoutLookback;
		private readonly double _breakoutClvMin;
		private readonly int _climaxLookback;
		private readonly double _climaxRangeMult;
		private readonly double _climaxBodyRatioMax;

		private readonly PabRingBuffer<PabBarInfo> _bars;

		// Pullback-sequence state — identical state machine to BarClassifier.mqh.
		private bool _haveLeg;
		private bool _legIsBull;
		private double _legExtreme;
		private int _pullbackCount;
		private bool _havePrevPullback;
		private double _prevPullbackExtreme;

		public PabBarClassifier(double dojiBodyRatio = 0.30, int maxStored = 2000, double clvFavorableMin = 0.15,
			int breakoutLookback = 10, double breakoutClvMin = 0.5,
			int climaxLookback = 20, double climaxRangeMult = 2.0, double climaxBodyRatioMax = 0.35)
		{
			_dojiBodyRatio = dojiBodyRatio;
			_clvFavorableMin = clvFavorableMin;
			_breakoutLookback = Math.Max(1, breakoutLookback);
			_breakoutClvMin = breakoutClvMin;
			_climaxLookback = Math.Max(2, climaxLookback);
			_climaxRangeMult = climaxRangeMult;
			_climaxBodyRatioMax = climaxBodyRatioMax;
			_bars = new PabRingBuffer<PabBarInfo>(maxStored);
			Reset();
		}

		public void Reset()
		{
			_bars.Clear();
			_haveLeg = false; _legIsBull = false; _legExtreme = 0.0; _pullbackCount = 0;
			_havePrevPullback = false; _prevPullbackExtreme = 0.0;
		}

		public int Count { get { return _bars.Count; } }
		public PabBarInfo GetBar(int i) { return i >= 0 && i < _bars.Count ? _bars[i] : null; }

		private PabBarType ClassifyType(double o, double h, double l, double c, double prevH, double prevL, bool havePrev)
		{
			if (havePrev && h <= prevH && l >= prevL) return PabBarType.Inside;
			if (havePrev && h >= prevH && l <= prevL) return PabBarType.Outside;
			double ratio = PabUtils.BodyRatio(o, h, l, c);
			if (ratio < _dojiBodyRatio) return PabBarType.Doji;
			return c > o ? PabBarType.BullTrend : PabBarType.BearTrend;
		}

		private bool IsBreakoutBar(PabBarInfo bar, IPabPriceSeries s, int barsAvailable)
		{
			if (bar.BarType != PabBarType.BullTrend && bar.BarType != PabBarType.BearTrend) return false;
			bool bull = bar.BarType == PabBarType.BullTrend;
			if (bull && bar.Clv < _breakoutClvMin) return false;
			if (!bull && bar.Clv > -_breakoutClvMin) return false;

			int lookEnd = Math.Min(barsAvailable - 1, _breakoutLookback);
			if (lookEnd < 1) return false;
			for (int i = 1; i <= lookEnd; i++)
			{
				if (bull && s.High(i) >= bar.High) return false;
				if (!bull && s.Low(i) <= bar.Low) return false;
			}
			return true;
		}

		private bool IsClimaxBar(PabBarInfo bar, IPabPriceSeries s, int barsAvailable)
		{
			double avgRange = PabUtils.AverageRange(s, 1, _climaxLookback, barsAvailable);
			if (avgRange <= 0.0) return false;
			bool bigRange = bar.Range >= _climaxRangeMult * avgRange;
			bool weakClose = bar.BodyRatio <= _climaxBodyRatioMax;
			return bigRange && weakClose;
		}

		private PabSignalQuality ScorePullback(PabBarInfo bar, bool bullLeg)
		{
			int score = 0;
			bool favorableClose = bullLeg ? bar.Clv >= _clvFavorableMin : bar.Clv <= -_clvFavorableMin;
			if (favorableClose) score++;
			if (_havePrevPullback)
			{
				bool shallower = bullLeg ? bar.Low > _prevPullbackExtreme : bar.High < _prevPullbackExtreme;
				if (shallower) score++;
			}
			return score >= 2 ? PabSignalQuality.Strong : score == 1 ? PabSignalQuality.Moderate : PabSignalQuality.Weak;
		}

		private void UpdatePullbackState(PabBarInfo bar)
		{
			if (!_haveLeg)
			{
				if (bar.BarType == PabBarType.BullTrend) { _haveLeg = true; _legIsBull = true; _legExtreme = bar.High; _pullbackCount = 0; }
				else if (bar.BarType == PabBarType.BearTrend) { _haveLeg = true; _legIsBull = false; _legExtreme = bar.Low; _pullbackCount = 0; }
				bar.PullbackType = PabPullbackType.None; bar.PullbackIndex = 0; bar.SignalQuality = PabSignalQuality.NA;
				_havePrevPullback = false;
				return;
			}

			if (_legIsBull)
			{
				if (bar.High > _legExtreme)
				{
					_legExtreme = bar.High; _pullbackCount = 0;
					bar.PullbackType = PabPullbackType.None; bar.PullbackIndex = 0; bar.SignalQuality = PabSignalQuality.NA;
					_havePrevPullback = false;
				}
				else
				{
					_pullbackCount++;
					bar.PullbackIndex = _pullbackCount;
					bar.PullbackType = _pullbackCount == 1 ? PabPullbackType.H1 : _pullbackCount == 2 ? PabPullbackType.H2 : PabPullbackType.H3Plus;
					bar.SignalQuality = ScorePullback(bar, true);
					_prevPullbackExtreme = bar.Low; _havePrevPullback = true;
				}
			}
			else
			{
				if (bar.Low < _legExtreme)
				{
					_legExtreme = bar.Low; _pullbackCount = 0;
					bar.PullbackType = PabPullbackType.None; bar.PullbackIndex = 0; bar.SignalQuality = PabSignalQuality.NA;
					_havePrevPullback = false;
				}
				else
				{
					_pullbackCount++;
					bar.PullbackIndex = _pullbackCount;
					bar.PullbackType = _pullbackCount == 1 ? PabPullbackType.L1 : _pullbackCount == 2 ? PabPullbackType.L2 : PabPullbackType.L3Plus;
					bar.SignalQuality = ScorePullback(bar, false);
					_prevPullbackExtreme = bar.High; _havePrevPullback = true;
				}
			}

			// Leg flip: opposite trend bar breaking the extreme after >=2 pullback bars.
			if (_legIsBull && bar.BarType == PabBarType.BearTrend && bar.Low < _legExtreme && _pullbackCount >= 2)
			{
				_legIsBull = false; _legExtreme = bar.Low; _pullbackCount = 0;
				bar.PullbackType = PabPullbackType.None; bar.PullbackIndex = 0; bar.SignalQuality = PabSignalQuality.NA;
				_havePrevPullback = false;
			}
			else if (!_legIsBull && bar.BarType == PabBarType.BullTrend && bar.High > _legExtreme && _pullbackCount >= 2)
			{
				_legIsBull = true; _legExtreme = bar.High; _pullbackCount = 0;
				bar.PullbackType = PabPullbackType.None; bar.PullbackIndex = 0; bar.SignalQuality = PabSignalQuality.NA;
				_havePrevPullback = false;
			}
		}

		// Call once per bar (barsAgo=0 in 's' is the bar being processed).
		public PabBarInfo Update(IPabPriceSeries s, int barsAvailable)
		{
			var bar = new PabBarInfo
			{
				Time = s.Time(0), Open = s.Open(0), High = s.High(0), Low = s.Low(0), Close = s.Close(0)
			};
			bar.BodySize = PabUtils.BodySize(bar.Open, bar.Close);
			bar.Range = PabUtils.BarRange(bar.High, bar.Low);
			bar.BodyRatio = PabUtils.BodyRatio(bar.Open, bar.High, bar.Low, bar.Close);
			bar.Clv = PabUtils.CloseLocationValue(bar.High, bar.Low, bar.Close);
			bar.IsBullish = bar.Close > bar.Open;

			bool havePrev = barsAvailable > 1;
			double prevH = havePrev ? s.High(1) : 0.0;
			double prevL = havePrev ? s.Low(1) : 0.0;
			bar.BarType = ClassifyType(bar.Open, bar.High, bar.Low, bar.Close, prevH, prevL, havePrev);

			bar.IsBreakoutBar = IsBreakoutBar(bar, s, barsAvailable);
			bar.IsClimax = IsClimaxBar(bar, s, barsAvailable);

			UpdatePullbackState(bar);
			_bars.PushFront(bar);
			return bar;
		}
	}

	#endregion

	#region PabSwingDetector (mirrors SwingDetector.mqh)

	public class PabSwingDetector
	{
		private readonly int _fractalLegs;
		private readonly PabRingBuffer<PabSwingPoint> _swings;

		public PabSwingDetector(int fractalLegs = 2, int maxStored = 500)
		{
			_fractalLegs = Math.Max(1, fractalLegs);
			_swings = new PabRingBuffer<PabSwingPoint>(maxStored);
		}

		public void Reset() { _swings.Clear(); }
		public int Count { get { return _swings.Count; } }
		public PabSwingPoint GetSwing(int i) { return i >= 0 && i < _swings.Count ? _swings[i] : null; }

		public PabSwingPoint LatestOfType(PabSwingType t)
		{
			for (int i = 0; i < _swings.Count; i++) if (_swings[i].Type == t) return _swings[i];
			return null;
		}

		// Confirms the fractal centered 'fractalLegs' bars back from the bar
		// just processed (barsAgo=0), since that's the first call with enough
		// newer bars on both sides. Returns any newly confirmed swing(s).
		public List<PabSwingPoint> Update(IPabPriceSeries s, int barsAvailable)
		{
			var found = new List<PabSwingPoint>();
			int c = _fractalLegs;
			if (barsAvailable <= 2 * _fractalLegs) return found;

			bool isHigh = true, isLow = true;
			double hc = s.High(c), lc = s.Low(c);
			for (int k = 1; k <= _fractalLegs; k++)
			{
				if (s.High(c - k) >= hc || s.High(c + k) >= hc) isHigh = false;
				if (s.Low(c - k) <= lc || s.Low(c + k) <= lc) isLow = false;
				if (!isHigh && !isLow) break;
			}

			if (isHigh) { var sp = new PabSwingPoint { Time = s.Time(c), Price = hc, Type = PabSwingType.High }; _swings.PushFront(sp); found.Add(sp); }
			if (isLow) { var sp = new PabSwingPoint { Time = s.Time(c), Price = lc, Type = PabSwingType.Low }; _swings.PushFront(sp); found.Add(sp); }
			return found;
		}
	}

	#endregion

	#region PabTradingRangeDetector (mirrors TradingRangeDetector.mqh)

	public class PabTradingRangeDetector
	{
		private readonly int _lookback;
		private readonly double _overlapThreshold;
		private readonly double _displaceThreshold;
		private PabMarketState _state = PabMarketState.TradingRange;
		private readonly PabTradingRangeInfo _current = new PabTradingRangeInfo();

		public PabTradingRangeDetector(int lookback = 20, double overlapThreshold = 0.55, double displaceThreshold = 3.0)
		{
			_lookback = Math.Max(5, lookback);
			_overlapThreshold = overlapThreshold;
			_displaceThreshold = displaceThreshold;
		}

		public void Reset() { _state = PabMarketState.TradingRange; _current.Active = false; }
		public PabMarketState State { get { return _state; } }
		public PabTradingRangeInfo Current { get { return _current; } }

		// avgRangeAt: dependency-injected average-range/ATR accessor (barsAgo -> value).
		// Pass the real ATR() series's indexer here for MT5-parity, or PabUtils.AverageRange
		// as a fallback — same idea as CTradingRangeDetector.SetATRSeries() in MQL5.
		public void Update(IPabPriceSeries s, int barsAvailable, Func<int, double> avgRangeAt)
		{
			if (barsAvailable < _lookback) return;
			int last = _lookback - 1;

			double overlapSum = 0.0; int overlapN = 0;
			for (int i = 0; i < last; i++)
			{
				overlapSum += PabUtils.RangeOverlap(s.High(i), s.Low(i), s.High(i + 1), s.Low(i + 1));
				overlapN++;
			}
			double avgOverlap = overlapN > 0 ? overlapSum / overlapN : 0.0;

			double avgRange = avgRangeAt(0);
			double netMove = s.Close(0) - s.Close(last);
			double displacement = avgRange > 0.0 ? Math.Abs(netMove) / avgRange : 0.0;

			double windowHigh = s.High(0), windowLow = s.Low(0);
			for (int i = 0; i <= last; i++) { windowHigh = Math.Max(windowHigh, s.High(i)); windowLow = Math.Min(windowLow, s.Low(i)); }

			if (displacement >= _displaceThreshold && avgOverlap < _overlapThreshold)
			{
				_state = netMove > 0 ? PabMarketState.BullTrend : PabMarketState.BearTrend;
				_current.Active = false;
			}
			else if (avgOverlap >= _overlapThreshold)
			{
				_state = PabMarketState.TradingRange;
				_current.Active = true; _current.Top = windowHigh; _current.Bottom = windowLow;
				_current.StartTime = s.Time(last); _current.EndTime = s.Time(0); _current.OverlapRatio = avgOverlap;
			}
			else
			{
				_state = PabMarketState.Transition;
			}
		}
	}

	#endregion

	#region PabPatternDetector (mirrors PatternDetector.mqh)

	public class PabPatternDetector
	{
		private readonly double _similarityPct;
		private readonly double _convergenceMin;
		private readonly PabPatternInfo _last = new PabPatternInfo();

		public PabPatternDetector(double similarityPct = 0.0015, double convergenceMin = 0.15)
		{
			_similarityPct = similarityPct; _convergenceMin = convergenceMin;
		}

		public void Reset() { _last.Type = PabPatternType.None; _last.Note = ""; }
		public PabPatternInfo LastPattern { get { return _last; } }

		private bool NearlyEqual(double a, double b)
		{
			double avg = (Math.Abs(a) + Math.Abs(b)) / 2.0;
			return avg <= 0.0 ? a == b : Math.Abs(a - b) / avg <= _similarityPct;
		}

		// swings[0] = newest, same convention as PabSwingDetector.
		public bool AnalyzeSwings(IReadOnlyList<PabSwingPoint> swings)
		{
			var highs = new List<PabSwingPoint>(); var lows = new List<PabSwingPoint>();
			for (int i = 0; i < swings.Count && (highs.Count < 3 || lows.Count < 3); i++)
			{
				if (swings[i].Type == PabSwingType.High && highs.Count < 3) highs.Add(swings[i]);
				if (swings[i].Type == PabSwingType.Low && lows.Count < 3) lows.Add(swings[i]);
			}
			if (highs.Count < 2 || lows.Count < 2) { _last.Type = PabPatternType.None; return false; }

			if (highs.Count >= 2 && NearlyEqual(highs[0].Price, highs[1].Price))
			{
				_last.Type = PabPatternType.DoubleTop; _last.StartTime = highs[1].Time; _last.EndTime = highs[0].Time;
				_last.Note = "Double Top ~" + highs[0].Price.ToString("F5");
				return true;
			}
			if (lows.Count >= 2 && NearlyEqual(lows[0].Price, lows[1].Price))
			{
				_last.Type = PabPatternType.DoubleBottom; _last.StartTime = lows[1].Time; _last.EndTime = lows[0].Time;
				_last.Note = "Double Bottom ~" + lows[0].Price.ToString("F5");
				return true;
			}

			bool higherHighs = highs[0].Price > highs[1].Price, higherLows = lows[0].Price > lows[1].Price;
			bool lowerHighs = highs[0].Price < highs[1].Price, lowerLows = lows[0].Price < lows[1].Price;

			if (higherHighs && higherLows)
			{
				_last.Type = PabPatternType.HigherHighsLows;
				_last.StartTime = MinTime(highs[1].Time, lows[1].Time); _last.EndTime = MaxTime(highs[0].Time, lows[0].Time);
				_last.Note = "Higher-High / Higher-Low structure (bull)";
				return true;
			}
			if (lowerHighs && lowerLows)
			{
				_last.Type = PabPatternType.LowerHighsLows;
				_last.StartTime = MinTime(highs[1].Time, lows[1].Time); _last.EndTime = MaxTime(highs[0].Time, lows[0].Time);
				_last.Note = "Lower-High / Lower-Low structure (bear)";
				return true;
			}

			double highSlope = PabUtils.Slope(0, highs[1].Price, 1, highs[0].Price);
			double lowSlope = PabUtils.Slope(0, lows[1].Price, 1, lows[0].Price);
			if (highSlope < -_convergenceMin && lowSlope > _convergenceMin)
			{
				_last.Type = PabPatternType.Triangle;
				_last.StartTime = MinTime(highs[1].Time, lows[1].Time); _last.EndTime = MaxTime(highs[0].Time, lows[0].Time);
				_last.Note = "Converging triangle";
				return true;
			}

			if (highs.Count >= 3 && lows.Count >= 3)
			{
				bool risingHighs = highs[0].Price > highs[1].Price && highs[1].Price > highs[2].Price;
				bool risingLows = lows[0].Price > lows[1].Price && lows[1].Price > lows[2].Price;
				bool fallingHighs = highs[0].Price < highs[1].Price && highs[1].Price < highs[2].Price;
				bool fallingLows = lows[0].Price < lows[1].Price && lows[1].Price < lows[2].Price;

				if (risingHighs && risingLows)
				{
					_last.Type = PabPatternType.WedgeRising;
					_last.StartTime = MinTime(highs[2].Time, lows[2].Time); _last.EndTime = MaxTime(highs[0].Time, lows[0].Time);
					_last.Note = "3-push rising wedge (bearish per Brooks)";
					return true;
				}
				if (fallingHighs && fallingLows)
				{
					_last.Type = PabPatternType.WedgeFalling;
					_last.StartTime = MinTime(highs[2].Time, lows[2].Time); _last.EndTime = MaxTime(highs[0].Time, lows[0].Time);
					_last.Note = "3-push falling wedge (bullish per Brooks)";
					return true;
				}
			}

			_last.Type = PabPatternType.None;
			return false;
		}

		private static DateTime MinTime(DateTime a, DateTime b) { return a < b ? a : b; }
		private static DateTime MaxTime(DateTime a, DateTime b) { return a > b ? a : b; }
	}

	#endregion

	#region PabAlwaysInTracker (mirrors AlwaysInTracker.mqh)

	public class PabAlwaysInTracker
	{
		private PabAlwaysInState _state = PabAlwaysInState.None;
		private double _referenceExtreme;

		public void Reset() { _state = PabAlwaysInState.None; _referenceExtreme = 0.0; }
		public PabAlwaysInState State { get { return _state; } }

		public void Evaluate(double closePrice, PabSwingPoint latestHigh, PabSwingPoint latestLow)
		{
			if (_state == PabAlwaysInState.None)
			{
				if (latestHigh != null && closePrice > latestHigh.Price) { _state = PabAlwaysInState.Long; _referenceExtreme = latestLow != null ? latestLow.Price : 0.0; }
				else if (latestLow != null && closePrice < latestLow.Price) { _state = PabAlwaysInState.Short; _referenceExtreme = latestHigh != null ? latestHigh.Price : 0.0; }
				return;
			}

			if (_state == PabAlwaysInState.Long && latestLow != null && closePrice < latestLow.Price)
			{
				_state = PabAlwaysInState.Short; _referenceExtreme = latestHigh != null ? latestHigh.Price : 0.0;
			}
			else if (_state == PabAlwaysInState.Short && latestHigh != null && closePrice > latestHigh.Price)
			{
				_state = PabAlwaysInState.Long; _referenceExtreme = latestLow != null ? latestLow.Price : 0.0;
			}
		}
	}

	#endregion

	#region PabMeasuredMoveDetector (mirrors MeasuredMoveDetector.mqh)

	public class PabMeasuredMoveDetector
	{
		private readonly PabMeasuredMoveInfo _current = new PabMeasuredMoveInfo();
		public void Reset() { _current.Active = false; }
		public PabMeasuredMoveInfo Current { get { return _current; } }

		public bool AnalyzeSwings(IReadOnlyList<PabSwingPoint> swings)
		{
			if (swings.Count < 3) { _current.Active = false; return false; }

			PabSwingPoint pivot = swings[0], legEnd = swings[1], legStart = swings[2];
			if (legStart.Type != pivot.Type || legEnd.Type == pivot.Type) { _current.Active = false; return false; }

			double legSize = Math.Abs(legEnd.Price - legStart.Price);
			if (legSize <= 0.0) { _current.Active = false; return false; }

			bool bullish = legEnd.Price > legStart.Price;
			_current.Active = true; _current.IsBullish = bullish;
			_current.Leg1Start = legStart.Price; _current.Leg1End = legEnd.Price;
			_current.PivotPrice = pivot.Price; _current.PivotTime = pivot.Time;
			_current.TargetPrice = bullish ? pivot.Price + legSize : pivot.Price - legSize;
			return true;
		}
	}

	#endregion

	#region PabChartRenderer (mirrors ChartRenderer.mqh — the ONLY class that draws)

	public class PabChartRenderer
	{
		private readonly Indicator _host;
		private readonly string _prefix;

		public Brush ColorBull = Brushes.DodgerBlue;
		public Brush ColorBear = Brushes.Crimson;
		public Brush ColorSwingHigh = Brushes.Orange;
		public Brush ColorSwingLow = Brushes.Lime;
		public Brush ColorRange = Brushes.Khaki;
		public Brush ColorPattern = Brushes.Magenta;
		public Brush ColorBreakout = Brushes.Yellow;
		public Brush ColorClimax = Brushes.Red;
		public Brush ColorMeasuredMove = Brushes.Aqua;

		public bool ShowPullbackLabels = true, ShowSwings = true, ShowRange = true, ShowPatterns = true;
		public bool ShowBreakouts = true, ShowClimax = true, ShowMeasuredMove = true;

		public PabChartRenderer(Indicator host, string prefix) { _host = host; _prefix = prefix; }

		private string Tag(string kind, string uniq) { return _prefix + "_" + kind + "_" + uniq; }

		public void DrawBarLabel(PabBarInfo bar)
		{
			if (!ShowPullbackLabels || bar.PullbackType == PabPullbackType.None) return;
			string txt;
			switch (bar.PullbackType)
			{
				case PabPullbackType.H1: txt = "H1"; break;
				case PabPullbackType.H2: txt = "H2"; break;
				case PabPullbackType.H3Plus: txt = "H3+"; break;
				case PabPullbackType.L1: txt = "L1"; break;
				case PabPullbackType.L2: txt = "L2"; break;
				case PabPullbackType.L3Plus: txt = "L3+"; break;
				default: return;
			}
			if (bar.SignalQuality == PabSignalQuality.Strong) txt += "*";

			bool isHigh = bar.PullbackType == PabPullbackType.H1 || bar.PullbackType == PabPullbackType.H2 || bar.PullbackType == PabPullbackType.H3Plus;
			double offset = bar.Range * 0.15;
			double y = isHigh ? bar.High + offset : bar.Low - offset;
			Draw.Text(_host, Tag("LBL", bar.Time.Ticks.ToString()), txt, bar.Time, y, isHigh ? ColorBear : ColorBull);
		}

		public void DrawSwing(PabSwingPoint sp)
		{
			if (!ShowSwings) return;
			string tag = Tag("SWING", sp.Time.Ticks + (sp.Type == PabSwingType.High ? "H" : "L"));
			// NinjaTrader's arrow drawing tools already offset the arrow shape
			// from the anchor point, so the swing price itself is the right anchor.
			if (sp.Type == PabSwingType.High) Draw.ArrowDown(_host, tag, sp.Time, sp.Price, ColorSwingHigh);
			else Draw.ArrowUp(_host, tag, sp.Time, sp.Price, ColorSwingLow);
		}

		public void DrawTradingRange(PabTradingRangeInfo r)
		{
			if (!ShowRange || !r.Active) return;
			Draw.Rectangle(_host, Tag("RANGE", "current"), r.StartTime, r.Top, r.EndTime, r.Bottom, ColorRange, ColorRange, 10);
		}

		public void DrawBreakoutMarker(PabBarInfo bar)
		{
			if (!ShowBreakouts || !bar.IsBreakoutBar) return;
			bool bull = bar.BarType == PabBarType.BullTrend;
			double offset = bar.Range * 0.30;
			double y = bull ? bar.Low - offset : bar.High + offset;
			string tag = Tag("BRK", bar.Time.Ticks.ToString());
			if (bull) Draw.ArrowUp(_host, tag, bar.Time, y, ColorBreakout);
			else Draw.ArrowDown(_host, tag, bar.Time, y, ColorBreakout);
		}

		public void DrawClimaxMarker(PabBarInfo bar)
		{
			if (!ShowClimax || !bar.IsClimax) return;
			double y = (bar.High + bar.Low) / 2.0;
			Draw.Diamond(_host, Tag("CLX", bar.Time.Ticks.ToString()), bar.Time, y, ColorClimax);
		}

		public void DrawMeasuredMove(PabMeasuredMoveInfo mm, DateTime currentBarTime)
		{
			if (!ShowMeasuredMove || !mm.Active) return;
			Draw.Line(_host, Tag("MM", "target"), mm.PivotTime, mm.TargetPrice, currentBarTime, mm.TargetPrice, ColorMeasuredMove);
			Draw.Text(_host, Tag("MM", "label"), "MM target " + mm.TargetPrice.ToString("F5"), currentBarTime, mm.TargetPrice, ColorMeasuredMove);
		}

		public void DrawPattern(PabPatternInfo p, double topPrice)
		{
			if (!ShowPatterns || p.Type == PabPatternType.None) return;
			Draw.Text(_host, Tag("PATTERN", p.EndTime.Ticks.ToString()), p.Note, p.EndTime, topPrice, ColorPattern);
		}

		public void DrawStatePanel(string text)
		{
			Draw.TextFixed(_host, Tag("PANEL", "state"), text, TextPosition.TopLeft);
		}
	}

	#endregion

	// =====================================================================
	// Orchestrator: the actual NinjaScript indicator. Mirrors PriceActionBarByBar.mq5's
	// OnCalculate() — here it's OnBarUpdate(), called once per closed bar.
	// =====================================================================
	public class PriceActionBarByBar : Indicator
	{
		#region Inputs (mirror the MQL5 indicator's input groups)

		[NinjaScriptProperty, Range(0.0, 1.0)]
		[Display(Name = "Doji Body Ratio", GroupName = "01 Bar Classification", Order = 1)]
		public double DojiBodyRatio { get; set; }

		[NinjaScriptProperty, Range(0.0, 1.0)]
		[Display(Name = "CLV Favorable Min", GroupName = "01 Bar Classification", Order = 2)]
		public double ClvFavorableMin { get; set; }

		[NinjaScriptProperty, Range(1, 20)]
		[Display(Name = "Fractal Legs", GroupName = "02 Swing Detection", Order = 1)]
		public int FractalLegs { get; set; }

		[NinjaScriptProperty, Range(5, 500)]
		[Display(Name = "Regime Lookback", GroupName = "03 Trading Range", Order = 1)]
		public int RegimeLookback { get; set; }

		[NinjaScriptProperty, Range(0.0, 1.0)]
		[Display(Name = "Overlap Threshold", GroupName = "03 Trading Range", Order = 2)]
		public double OverlapThreshold { get; set; }

		[NinjaScriptProperty, Range(0.0, double.MaxValue)]
		[Display(Name = "Displace Threshold", GroupName = "03 Trading Range", Order = 3)]
		public double DisplaceThreshold { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Use Real ATR", GroupName = "03 Trading Range", Order = 4)]
		public bool UseRealAtr { get; set; }

		[NinjaScriptProperty, Range(1, 200)]
		[Display(Name = "ATR Period", GroupName = "03 Trading Range", Order = 5)]
		public int AtrPeriod { get; set; }

		[NinjaScriptProperty, Range(0.0, 1.0)]
		[Display(Name = "Swing Similarity %", GroupName = "04 Pattern Detection", Order = 1)]
		public double SwingSimilarityPct { get; set; }

		[NinjaScriptProperty, Range(0.0, double.MaxValue)]
		[Display(Name = "Convergence Min", GroupName = "04 Pattern Detection", Order = 2)]
		public double ConvergenceMin { get; set; }

		[NinjaScriptProperty, Range(1, 100)]
		[Display(Name = "Breakout Lookback", GroupName = "05 Breakout Climax", Order = 1)]
		public int BreakoutLookback { get; set; }

		[NinjaScriptProperty, Range(0.0, 1.0)]
		[Display(Name = "Breakout CLV Min", GroupName = "05 Breakout Climax", Order = 2)]
		public double BreakoutClvMin { get; set; }

		[NinjaScriptProperty, Range(2, 200)]
		[Display(Name = "Climax Lookback", GroupName = "05 Breakout Climax", Order = 3)]
		public int ClimaxLookback { get; set; }

		[NinjaScriptProperty, Range(0.1, 20.0)]
		[Display(Name = "Climax Range Mult", GroupName = "05 Breakout Climax", Order = 4)]
		public double ClimaxRangeMult { get; set; }

		[NinjaScriptProperty, Range(0.0, 1.0)]
		[Display(Name = "Climax Body Ratio Max", GroupName = "05 Breakout Climax", Order = 5)]
		public double ClimaxBodyRatioMax { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Show State Panel", GroupName = "06 Display", Order = 1)]
		public bool ShowStatePanel { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Show Pullback Labels", GroupName = "06 Display", Order = 2)]
		public bool ShowPullbackLabels { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Show Swings", GroupName = "06 Display", Order = 3)]
		public bool ShowSwings { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Show Trading Range", GroupName = "06 Display", Order = 4)]
		public bool ShowRange { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Show Patterns", GroupName = "06 Display", Order = 5)]
		public bool ShowPatterns { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Show Breakouts", GroupName = "06 Display", Order = 6)]
		public bool ShowBreakouts { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Show Climax", GroupName = "06 Display", Order = 7)]
		public bool ShowClimax { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Show Measured Move", GroupName = "06 Display", Order = 8)]
		public bool ShowMeasuredMove { get; set; }

		// Per-element COLORS are intentionally not exposed as NinjaScriptProperty
		// inputs here — NinjaScript's Brush inputs need extra XML-serialization
		// boilerplate (a shadow string property + [XmlIgnore], the well-known
		// NT8 workaround) that would roughly double this section for a feature
		// most users set once and forget. Edit PabChartRenderer's public Brush
		// fields (ColorBull, ColorBear, ColorSwingHigh, ...) directly near the
        // top of that class if you want different defaults — see README.md.

		#endregion

		private PabBarClassifier _classifier;
		private PabSwingDetector _swings;
		private PabTradingRangeDetector _range;
		private PabPatternDetector _patterns;
		private PabAlwaysInTracker _alwaysIn;
		private PabMeasuredMoveDetector _measuredMove;
		private PabChartRenderer _renderer;
		private IPabPriceSeries _series;
		private ATR _atr; // NinjaTrader's built-in ATR sub-indicator — no handle/CopyBuffer dance needed

		protected override void OnStateChange()
		{
			if (State == State.SetDefaults)
			{
				Description = "OOP price-action bar-by-bar analyzer, ported from the MQL5 PriceActionBarByBar project (Phase 4).";
				Name = "PriceActionBarByBar";
				Calculate = Calculate.OnBarClose;
				IsOverlay = true;
				DisplayInDataBox = false;
				PaintPriceMarkers = false;
				IsSuspendedWhileInactive = true;

				DojiBodyRatio = 0.30; ClvFavorableMin = 0.15;
				FractalLegs = 2;
				RegimeLookback = 20; OverlapThreshold = 0.55; DisplaceThreshold = 3.0; UseRealAtr = true; AtrPeriod = 14;
				SwingSimilarityPct = 0.15; ConvergenceMin = 0.15;
				BreakoutLookback = 10; BreakoutClvMin = 0.50; ClimaxLookback = 20; ClimaxRangeMult = 2.0; ClimaxBodyRatioMax = 0.35;
				ShowStatePanel = true;
				ShowPullbackLabels = true; ShowSwings = true; ShowRange = true; ShowPatterns = true;
				ShowBreakouts = true; ShowClimax = true; ShowMeasuredMove = true;
			}
			else if (State == State.Configure)
			{
				if (UseRealAtr) _atr = ATR(AtrPeriod); // sub-indicators must be instantiated in State.Configure
			}
			else if (State == State.DataLoaded)
			{
				_classifier = new PabBarClassifier(DojiBodyRatio, 2000, ClvFavorableMin,
					BreakoutLookback, BreakoutClvMin, ClimaxLookback, ClimaxRangeMult, ClimaxBodyRatioMax);
				_swings = new PabSwingDetector(FractalLegs);
				_range = new PabTradingRangeDetector(RegimeLookback, OverlapThreshold, DisplaceThreshold);
				_patterns = new PabPatternDetector(SwingSimilarityPct / 100.0, ConvergenceMin);
				_alwaysIn = new PabAlwaysInTracker();
				_measuredMove = new PabMeasuredMoveDetector();
				_series = new PabNinjaSeriesAdapter(this);
				_renderer = new PabChartRenderer(this, "PAB")
				{
					ShowPullbackLabels = ShowPullbackLabels,
					ShowSwings = ShowSwings,
					ShowRange = ShowRange,
					ShowPatterns = ShowPatterns,
					ShowBreakouts = ShowBreakouts,
					ShowClimax = ShowClimax,
					ShowMeasuredMove = ShowMeasuredMove
				};
			}
		}

		protected override void OnBarUpdate()
		{
			if (CurrentBar < 10) return;
			int barsAvailable = CurrentBar + 1;

			// avgRangeAt(0): real ATR if enabled and warmed up, else the same
			// internal fallback CTradingRangeDetector.mqh uses without an
			// injected ATR series.
			Func<int, double> avgRangeAt = (barsAgo) =>
			{
				if (UseRealAtr && _atr != null && CurrentBar >= AtrPeriod) return _atr[barsAgo];
				return PabUtils.AverageRange(_series, barsAgo, RegimeLookback, barsAvailable);
			};

			PabBarInfo bar = _classifier.Update(_series, barsAvailable);
			List<PabSwingPoint> newSwings = _swings.Update(_series, barsAvailable);
			_range.Update(_series, barsAvailable, avgRangeAt);

			var swingList = new List<PabSwingPoint>(_swings.Count);
			for (int i = 0; i < _swings.Count; i++) swingList.Add(_swings.GetSwing(i));
			if (swingList.Count > 0)
			{
				_patterns.AnalyzeSwings(swingList);
				_measuredMove.AnalyzeSwings(swingList);
			}

			PabSwingPoint latestHigh = _swings.LatestOfType(PabSwingType.High);
			PabSwingPoint latestLow = _swings.LatestOfType(PabSwingType.Low);
			_alwaysIn.Evaluate(Close[0], latestHigh, latestLow);

			// --- rendering ---
			_renderer.DrawBarLabel(bar);
			_renderer.DrawBreakoutMarker(bar);
			_renderer.DrawClimaxMarker(bar);
			foreach (var sp in newSwings) _renderer.DrawSwing(sp);
			if (_range.Current.Active) _renderer.DrawTradingRange(_range.Current);
			if (_patterns.LastPattern.Type != PabPatternType.None) _renderer.DrawPattern(_patterns.LastPattern, High[0]);
			if (_measuredMove.Current.Active) _renderer.DrawMeasuredMove(_measuredMove.Current, Time[0]);

			if (ShowStatePanel)
			{
				string alwaysInLabel = _alwaysIn.State == PabAlwaysInState.Long ? "Long" : _alwaysIn.State == PabAlwaysInState.Short ? "Short" : "None";
				string stateLabel = _range.State == PabMarketState.BullTrend ? "Bull Trend" :
					_range.State == PabMarketState.BearTrend ? "Bear Trend" :
					_range.State == PabMarketState.TradingRange ? "Trading Range" : "Transition";
				_renderer.DrawStatePanel(string.Format("PriceActionBarByBar\nState: {0} | Always-In: {1}\nSwings: {2}",
					stateLabel, alwaysInLabel, _swings.Count));
			}
		}
	}
}
