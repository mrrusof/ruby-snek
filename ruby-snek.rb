#!/usr/bin/env ruby

require 'io/console'
require 'curses'

include Curses

def incrw x, hi
  if (x += 1) == hi
    return 0
  else
    return x
  end
end

def decrw x, hi
  if (x -= 1) < 0
    return hi - 1
  else
    return x
  end
end

def rand_pos maxy, maxx
  [Random.rand(maxy), Random.rand(maxx)]
end

def show_message msg
  width = msg.length + 6
  win = Window.new 5, width, ((lines - 5) / 2), ((cols - width) / 2)
  win.box ?|, ?-
  win.setpos 2, 3
  win.addstr msg
  win.refresh
  STDIN.getch
  win.close
end

class CircularQueue

  def initialize cap
    @size = @left = @right = 0
    @data = Array.new cap, nil
  end

  def queue x
    if @size == @data.length
      raise Exception.new 'Tried to queue element into full circular queue.'
    end
    @data[@right] = x
    @right = move_right @right
    @size += 1
    return x
  end

  def pop
    if @size == 0
      raise Exception.new 'Tried to pop element from empty circular queue.'
    end
    @right = move_left @right
    x = @data[@right]
    @size -= 1
    return x
  end

  def dequeue
    if @size == 0
      raise Exception.new 'Tried to dequeue element from empty circular queue.'
    end
    x = @data[@left]
    @left = move_right @left
    @size -= 1
    return x
  end

  def head
    if @size == 0
      raise Exception.new 'Tried to get head element from empty circular queue.'
    end
    return @data[move_left(@right)]
  end

  def tail
    if @size == 0
      raise Exception.new 'Tried to get tail element from empty cirular queue.'
    end
    return @data[@left]
  end

  def each
    i = @left
    begin
      yield @data[i]
    end while (i = move_right i) != @right
  end

  def all?
    i = @left
    while i < @right and yield @data[i]
      i = move_right i
    end
    return i == @right
  end

  private

  def move_right x
    incrw x, @data.length
  end

  def move_left x
    decrw x, @data.length
  end

end

class Snek

  BSEG = '*'
  CSEG = ' '
  DLEN = 5
  DDIR = 0

  attr_reader :eat_count

  def initialize win
    @win = win
    @eat_count = @to_grow = 0
    @dir = DDIR
    @body = CircularQueue.new @win.maxx * @win.maxy
    (1..DLEN).each { |c| @body.queue [0, c] }
  end

  def draw
    @body.each do |y, x|
      @win.setpos y, x
      @win.addch BSEG
    end
  end

  def move
    if @to_grow == 0
      @win.setpos *@body.dequeue
      @win.addch CSEG
    else
      @to_grow -= 1
    end
    @win.setpos *@body.queue(move_head)
    @win.addch BSEG
  end

  def turn d
    case d
    when :right
      @dir = incrw(@dir, 4)
    when :left
      @dir = decrw(@dir, 4)
    end
  end

  def eat? food
    return false unless touches? *food.pos
    @to_grow += food.to_grow
    @eat_count += 1
    return true
  end

  def touches? y, x
    pos = [y, x]
    return !@body.all? { |part| part != pos }
  end

  def is_alive?
    h = @body.pop
    no_hit = @body.all? { |part| part != h }
    @body.queue h
    return no_hit
  end

  private

  def head
    @body.head
  end

  def tail
    @body.tail
  end

  def move_head
    y, x = head
    case @dir
    when 0 # right
      [y, incrw(x, @win.maxx)]
    when 1 # down
      [incrw(y, @win.maxy), x]
    when 2 # left
      [y, decrw(x, @win.maxx)]
    when 3 # up
      [decrw(y, @win.maxy), x]
    end
  end

end

class Food

  BODY = '@'
  DGRO = 5

  attr_reader :pos, :to_grow

  def initialize win
    @win = win
    set_rand_pos
    @to_grow = DGRO
  end

  def draw
    @win.setpos *@pos
    @win.addch BODY
  end

  def set_rand_pos
    @pos = rand_pos @win.maxy, @win.maxx
  end

end

class KeyReader

  UP = "\e[A"
  LEFT = "\e[D"
  RIGHT = "\e[C"

  attr_reader :key

  def initialize
    @key = nil
    @listener = nil
  end

  def start_listening
    @listener = Thread.new { listen }
  end

  def listen
    while true
      key = STDIN.getch.to_s
      if key == "\e"
        key << STDIN.read_nonblock(3) rescue nil
        key << STDIN.read_nonblock(2) rescue nil
      end
      @key = key
    end
  end

  def stop_listening
    return if !@listener
    @listener.kill
    @listener.join
    @listener = nil
  end

  def clear_key
    @key = nil
  end
end

class Game

  TITLE = '..:: ~~ RubySnek ~~ ::..'
  SLOW = 0.0625
  FAST = 0.03125

  def setup
    init_screen
    crmode

    @border = Window.new (lines - 2), cols, 2, 0
    @border.box ?|, ?-
    @border.refresh

    @canvas = Window.new (lines - 4), (cols - 2), 3, 1

    @s = Snek.new @canvas
    @s.draw

    @f = Food.new @canvas
    @f.draw

    @header = Window.new 2, cols, 0, 0
    @header.setpos 0, (cols / 2 - TITLE.length / 2)
    @header.addstr TITLE
    show_score

    @kbd = KeyReader.new
    @kbd.start_listening
  end

  def teardown
    @kbd.stop_listening
    @canvas.close
    @border.close
    @header.close
  end

  def show_score
    @header.setpos 1, 0
    @header.addstr "score: #{@s.eat_count}"
    @header.refresh
  end

  def maybe_turn
    case @kbd.key
    when KeyReader::LEFT
      @s.turn :left
    when KeyReader::RIGHT
      @s.turn :right
    end
  end

  def maybe_eat
    if @s.eat? @f
      @f.set_rand_pos
      show_score
    end
  end

  def die
    @kbd.stop_listening
    show_message 'You died.'
  end

  def quit?
    @kbd.key == 'q'
  end

  def go_fast?
    @kbd.key == KeyReader::UP
  end

  def play
    begin
      setup
      timeout = SLOW
      while true
        @canvas.refresh
        sleep timeout
        if not @s.is_alive?
          die
          break
        end
        break if quit?
        if go_fast?
          timeout = FAST
        else
          timeout = SLOW
        end
        maybe_turn
        maybe_eat
        @f.draw
        @s.move
        @kbd.clear_key
      end
      teardown
    ensure
      close_screen
    end
  end

end

Game.new.play
