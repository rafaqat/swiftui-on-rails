# frozen_string_literal: true

module Demos
  # Session-backed inbox state for the Relay demo. Threads are fixed; the
  # session records which are read or archived and any messages the visitor
  # sent (each send earns a canned reply, so the conversation always moves).
  class RelayState
    THREADS = [
      {
        id: "launch-window",
        sender: "Flight Ops",
        subject: "Launch window moved up",
        seed_messages: [
          { from: "Flight Ops", body: "Weather cleared early — we can move the window up 40 minutes if range agrees." },
          { from: "Range Safety", body: "Range is green for the earlier slot. Need your go by 14:00." }
        ]
      },
      {
        id: "fuel-report",
        sender: "Propulsion",
        subject: "Fuel margin report attached",
        seed_messages: [
          { from: "Propulsion", body: "Margins holding at 6.2% after the trim burn. Full report in the workspace." }
        ]
      },
      {
        id: "crew-rotation",
        sender: "Crew Office",
        subject: "Rotation sign-off needed",
        seed_messages: [
          { from: "Crew Office", body: "Rotation draft is ready. Two swaps need your sign-off before Friday." }
        ]
      }
    ].freeze

    REPLIES = [
      "Copy that — noted on our end.",
      "Acknowledged. We'll fold that into the next briefing.",
      "Received. Anything else before the sync?"
    ].freeze

    MAX_SENT_MESSAGES = 20

    def initialize(stored = nil)
      stored = {} unless stored.is_a?(Hash)
      thread_ids = THREADS.map { |thread| thread[:id] }
      @read = Array(stored["read"]).map(&:to_s) & thread_ids
      @archived = Array(stored["archived"]).map(&:to_s) & thread_ids
      @sent = normalize_sent(stored["sent"], thread_ids)
    end

    def to_h
      { "read" => @read, "archived" => @archived, "sent" => @sent }
    end

    def inbox_threads
      THREADS.reject { |thread| @archived.include?(thread[:id]) }.map do |thread|
        thread.merge(unread: !@read.include?(thread[:id]))
      end
    end

    def archived_count
      @archived.length
    end

    def find_thread(id)
      thread = THREADS.find { |candidate| candidate[:id] == id.to_s }
      return nil if thread.nil? || @archived.include?(thread[:id])

      thread
    end

    def messages_for(thread_id)
      thread = THREADS.find { |candidate| candidate[:id] == thread_id.to_s } or return []
      thread[:seed_messages] + @sent.fetch(thread[:id], []).map(&:symbolize_keys)
    end

    def mark_read!(thread_id)
      id = thread_id.to_s
      @read << id if find_thread(id) && !@read.include?(id)
      self
    end

    def archive!(thread_id)
      id = thread_id.to_s
      raise ArgumentError, "unknown thread" unless find_thread(id)

      @archived << id unless @archived.include?(id)
      self
    end

    # Appends the visitor's message plus a deterministic canned reply.
    # Returns the reply body.
    def send_message!(thread_id, body)
      thread = find_thread(thread_id) or raise ArgumentError, "unknown thread"
      text = body.to_s.strip.first(280)
      raise ArgumentError, "message cannot be empty" if text.blank?

      bucket = (@sent[thread[:id]] ||= [])
      raise ArgumentError, "thread is full for this demo" if bucket.length >= MAX_SENT_MESSAGES

      reply = REPLIES[bucket.length % REPLIES.length]
      bucket << { "from" => "You", "body" => text }
      bucket << { "from" => thread[:sender], "body" => reply }
      reply
    end

    def reset!
      @read = []
      @archived = []
      @sent = {}
      self
    end

    private

    def normalize_sent(stored, thread_ids)
      return {} unless stored.is_a?(Hash)

      stored.each_with_object({}) do |(thread_id, messages), result|
        next unless thread_ids.include?(thread_id.to_s)

        result[thread_id.to_s] = Array(messages).first(MAX_SENT_MESSAGES).filter_map do |message|
          next unless message.is_a?(Hash)

          from = message["from"] || message[:from]
          body = message["body"] || message[:body]
          next if body.to_s.blank?

          { "from" => from.to_s.first(40), "body" => body.to_s.first(280) }
        end
      end
    end
  end
end
