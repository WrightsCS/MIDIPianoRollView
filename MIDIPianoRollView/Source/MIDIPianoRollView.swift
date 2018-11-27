//
//  MIDIPianoRollView.swift
//  MIDIPianoRollView
//
//  Created by cem.olcay on 26/11/2018.
//  Copyright © 2018 cemolcay. All rights reserved.
//

import UIKit
import ALKit
import MusicTheorySwift
import MIDIEventKit

/// Piano roll with customisable row count, row range, beat count and editable note cells.
public class MIDIPianoRollView: UIScrollView {
  /// Piano roll bars.
  public enum Bars {
    /// Fixed number of bars.
    case fixed(Int)
    /// Always a bar more than the last note's bar.
    case auto
  }

  /// Piano roll keys.
  public enum Keys {
    /// In a MIDI note range between 0 - 127
    case ranged(ClosedRange<UInt8>)
    /// In a musical scale.
    case scale(scale: Scale, minOctave: Int, maxOctave: Int)
    /// With custom keys.
    case custom([Pitch])

    /// Returns the pitches.
    public var pitches: [Pitch] {
      switch self {
      case .ranged(let range):
        return range.map({ Pitch(midiNote: Int($0)) })
      case .scale(let scale, let minOctave, let maxOctave):
        return scale.pitches(octaves: [Int](minOctave...maxOctave))
      case .custom(let pitches):
        return pitches
      }
    }
  }

  /// Zoom level of the piano roll that showing the mininum amount of beat.
  public enum ZoomLevel: Int {
    /// A beat represent whole note. See one beat in a bar.
    case wholeNotes = 1
    /// A beat represent sixtyfourth note. See 2 beats in a bar.
    case halfNotes = 2
    /// A beat represent quarter note. See 4 beats in a bar.
    case quarterNotes = 4
    /// A beat represent eighth note. See 8 beats in a bar.
    case eighthNotes = 8
    /// A beat represent sixteenth note. See 16 beats in a bar.
    case sixteenthNotes = 16
    /// A beat represent thirtysecond note. See 32 beats in a bar.
    case thirtysecondNotes = 32
    /// A beat represent sixtyfourth note. See 64 beats in a bar.
    case sixtyfourthNotes = 64

    /// Corresponding note value for the zoom level.
    public var noteValue: NoteValue {
      switch self {
      case .wholeNotes: return NoteValue(type: .whole)
      case .halfNotes: return NoteValue(type: .half)
      case .quarterNotes: return NoteValue(type: .quarter)
      case .eighthNotes: return NoteValue(type: .eighth)
      case .sixteenthNotes: return NoteValue(type: .sixteenth)
      case .thirtysecondNotes: return NoteValue(type: .thirtysecond)
      case .sixtyfourthNotes: return NoteValue(type: .sixtyfourth)
      }
    }

    /// Next level after zooming in.
    public var zoomedIn: ZoomLevel? {
      switch self {
      case .wholeNotes: return .halfNotes
      case .halfNotes: return .quarterNotes
      case .quarterNotes: return .eighthNotes
      case .eighthNotes: return .sixteenthNotes
      case .sixteenthNotes: return .thirtysecondNotes
      case .thirtysecondNotes: return .sixtyfourthNotes
      case .sixtyfourthNotes: return nil
      }
    }

    /// Previous level after zooming out.
    public var zoomedOut: ZoomLevel? {
      switch self {
      case .wholeNotes: return nil
      case .halfNotes: return .wholeNotes
      case .quarterNotes: return .halfNotes
      case .eighthNotes: return .quarterNotes
      case .sixteenthNotes: return .eighthNotes
      case .thirtysecondNotes: return .sixteenthNotes
      case .sixtyfourthNotes: return .thirtysecondNotes
      }
    }
  }

  /// All notes in the piano roll.
  public var notes: [MIDIPianoRollNote] = [] { didSet { reload() }}
  /// Time signature of the piano roll. Defaults to 4/4.
  public var timeSignature = TimeSignature() { didSet { reload() }}
  /// Bar count of the piano roll. Defaults to auto.
  public var bars: Bars = .auto { didSet { reload() }}
  /// Rendering note range of the piano roll. Defaults all MIDI notes, from 0 to 127.
  public var keys: Keys = .ranged(0...127) { didSet { reload() }}

  /// Current `ZoomLevel` of the piano roll.
  public var zoomLevel: ZoomLevel = .quarterNotes
  /// Minimum amount of the zoom level.
  public var minZoomLevel: ZoomLevel = .wholeNotes
  /// Maximum amount of the zoom level.
  public var maxZoomLevel: ZoomLevel = .sixteenthNotes
  /// Speed of zooming by pinch gesture.
  public var zoomSpeed: CGFloat = 0.4
  /// Maximum width of a beat on the bar, max zoomed in.
  public var maxBeatWidth: CGFloat = 40
  /// Minimum width of a beat on the bar, max zoomed out.
  public var minBeatWidth: CGFloat = 20
  /// Current with of a beat on the measure.
  public var beatWidth: CGFloat = 30
  /// Fixed height of the bar on the top.
  public var barHeight: CGFloat = 40
  /// Fixed left hand side row width on the piano roll.
  public var rowWidth: CGFloat = 60
  /// Current height of a row on the piano roll.
  public var rowHeight: CGFloat = 40
  /// Maximum height of a row on the piano roll.
  public var maxRowHeight: CGFloat = 150
  /// Minimum height of a row on the piano roll.
  public var minRowHeight: CGFloat = 30
  /// Label configuration for the measure beat labels.
  public var measureLabelConfig = UILabel()
  /// Global variable for all line widths.
  public var lineWidth: CGFloat = 0.5

  /// Enables/disables the edit mode. Defaults false.
  public var isEditing: Bool = false
  /// Enables/disables the zooming feature. Defaults true.
  public var isZoomingEnabled: Bool = true { didSet { pinchGesture.isEnabled = isZoomingEnabled }}
  /// Enables/disables the measure rendering. Defaults true.
  public var isMeasureEnabled: Bool = true { didSet { needsRedrawBar = true }}
  /// Enables/disables the multiple note cell editing at once. Defaults true.
  public var isMultipleEditingEnabled: Bool = true

  /// Pinch gesture for zooming.
  private var pinchGesture = UIPinchGestureRecognizer()
  /// Reference of the all row views.
  private var rowViews: [MIDIPianoRollRowView] = []
  /// Reference of the all cell views.
  private var cellViews: [MIDIPianoRollCellView] = []
  /// Reference of the all vertical measure beat lines.
  private var measureLines: [MIDIPianoRollMeasureLineLayer] = []
  /// Reference of the line on the top, drawn between measure and the piano roll grid.
  private var topMeasureLine = CALayer()
  /// Reference for controlling bar line redrawing in layoutSubview function.
  private var needsRedrawBar: Bool = false
  /// The last bar by notes position and duration. Updates on cells notes array change.
  private var lastBar: Int = 0

  /// Calculates the number of bars in the piano roll by the `BarCount` rule.
  private var barCount: Int {
    switch bars {
    case .fixed(let count):
      return count
    case .auto:
      return lastBar + 1
    }
  }

  // MARK: Init

  /// Initilizes the piano roll with a frame.
  ///
  /// - Parameter frame: Frame of the view.
  public override init(frame: CGRect) {
    super.init(frame: frame)
    commonInit()
  }

  /// Initilizes the piano roll with a coder.
  ///
  /// - Parameter aDecoder: Coder.
  public required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    commonInit()
  }

  /// Default initilizer.
  private func commonInit() {
    reload()
    pinchGesture.addTarget(self, action: #selector(didPinch(pinch:)))
    addGestureRecognizer(pinchGesture)
  }

  // MARK: Lifecycle

  /// Renders the piano roll.
  public override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    // Layout rows
    var currentY: CGFloat = isMeasureEnabled ? barHeight : 0
    for rowView in rowViews.reversed() {
      rowView.frame = CGRect(
        x: contentOffset.x,
        y: currentY,
        width: rowWidth,
        height: rowHeight)
      rowView.layer.zPosition = 1
      // Bottom line
      rowView.bottomLine.backgroundColor = UIColor.black.cgColor
      rowView.bottomLine.frame = CGRect(
        x: 0,
        y: rowView.frame.size.height - lineWidth,
        width: frame.size.width,
        height: lineWidth)
      // Go to next row.
      currentY += rowHeight
    }

    // Update content size vertically
    contentSize.height = currentY

    // Check if needs redraw measure lines.
    if needsRedrawBar {
      measureLines.forEach({ $0.removeFromSuperlayer() })
      measureLines = []
      topMeasureLine.removeFromSuperlayer()

      // Draw measure
      if isMeasureEnabled {
        topMeasureLine = CALayer()
        layer.addSublayer(topMeasureLine)
      }

      // Draw lines
      let lineCount = barCount * timeSignature.beats * zoomLevel.rawValue
      var linePosition: MIDIPianoRollPosition = .zero
      for _ in 0...lineCount {
        let line = MIDIPianoRollMeasureLineLayer()
        line.pianoRollPosition = linePosition
        line.showsBeatText = linePosition.isBarPosition
        layer.addSublayer(line)
        measureLines.append(line)

        // Draw beat text
        if line.showsBeatText && isMeasureEnabled {
          line.beatTextLayer.frame = CGRect(
            x: 0,
            y: barHeight - 15,
            width: max(barHeight, beatWidth),
            height: 15)
          line.beatTextLayer.fontSize = 13
          line.beatTextLayer.string = "\(linePosition)"
        }

        // Go next line
        linePosition = linePosition + zoomLevel.noteValue.pianoRollPosition
      }
      needsRedrawBar = false
    }

    // Start laying out bars after the key rows
    var currentX: CGFloat = rowWidth
    for line in measureLines {
      line.frame = CGRect(
        x: currentX,
        y: 0,
        width: lineWidth * (line.pianoRollPosition.isBarPosition ? 2 : 1),
        height: contentSize.height > 0 ? contentSize.height : frame.size.height)
      line.beatLineLayer.frame = CGRect(origin: .zero, size: line.frame.size)
      line.beatLineLayer.backgroundColor = line.pianoRollPosition.isBarPosition ? UIColor.black.cgColor : UIColor.gray.cgColor
      currentX += beatWidth
    }

    // Update content size horizontally
    contentSize.width = currentX

    // Update top line
    topMeasureLine.frame = CGRect(
      x: 0,
      y: barHeight - lineWidth,
      width: (contentSize.width > 0 ? contentSize.width : frame.size.width) - beatWidth,
      height: lineWidth)
    topMeasureLine.backgroundColor = UIColor.black.cgColor
    CATransaction.commit()
  }

  /// Removes each component and creates them again.
  public func reload() {
    // Reset row views.
    rowViews.forEach({ $0.removeFromSuperview() })
    rowViews = []
    // Reset cell views.
    cellViews.forEach({ $0.removeFromSuperview() })
    cellViews = []

    // Setup row views.
    for pitch in keys.pitches {
      let rowView = MIDIPianoRollRowView(pitch: pitch)
      addSubview(rowView)
      rowViews.append(rowView)
    }

    // Setup cell views.
    for note in notes {
      let cellView = MIDIPianoRollCellView(note: note)
      addSubview(cellView)
      cellViews.append(cellView)
    }

    // Update bar.
    lastBar = notes
      .map({ $0.position + $0.duration })
      .sorted(by: { $1 > $0 })
      .first?.bar ?? 0

    let barWidth = beatWidth * CGFloat(timeSignature.beats)
    if CGFloat(lastBar + 1) * barWidth < max(frame.size.width, frame.size.height) {
      lastBar = Int(ceil(Double(frame.size.width / barWidth)) + 1)
    }

    needsRedrawBar = true
  }

  // MARK: Zooming

  @objc private func didPinch(pinch: UIPinchGestureRecognizer) {
    switch pinch.state {
    case .began, .changed:
      guard pinch.numberOfTouches == 2 else { return }

      // Calculate pinch direction.
      let t1 = pinch.location(ofTouch: 0, in: self)
      let t2 = pinch.location(ofTouch: 1, in: self)
      let xD = abs(t1.x - t2.x)
      let yD = abs(t1.y - t2.y)
      var isVertical = true
      if (xD == 0) { isVertical = true }
      if (yD == 0) { isVertical = false }
      let ratio = xD / yD
      if (ratio > 2) { isVertical = false }
      if (ratio < 0.5) { isVertical = true }


      // Vertical zooming
      if isVertical {
        var rowScale = pinch.scale
        rowScale = ((rowScale - 1) * zoomSpeed) + 1
        rowScale = min(rowScale, maxRowHeight/rowHeight)
        rowScale = max(rowScale, minRowHeight/rowHeight)
        rowHeight *= rowScale
        setNeedsLayout()
        pinch.scale = 1
      } else { // Horizontal zooming
        var barScale = pinch.scale
        barScale = ((barScale - 1) * zoomSpeed) + 1
        barScale = min(barScale, maxBeatWidth/beatWidth)
        barScale = max(barScale, minBeatWidth/beatWidth)
        beatWidth *= barScale
        setNeedsLayout()
        pinch.scale = 1

        // Get in new zoom level.
        if beatWidth >= maxBeatWidth {
          if let zoom = zoomLevel.zoomedIn, zoom != maxZoomLevel {
            zoomLevel = zoom
            beatWidth = minBeatWidth
            needsRedrawBar = true
          }
        } else if beatWidth <= minBeatWidth {
          if let zoom = zoomLevel.zoomedOut, zoom != minZoomLevel {
            zoomLevel = zoom
            beatWidth = maxBeatWidth
            needsRedrawBar = true
          }
        }
      }
    default:
      return
    }
  }
}
