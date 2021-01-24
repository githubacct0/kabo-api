# frozen_string_literal: true

module MyLib
  class Icecube
    class << self
      # Upcoming billing date
      def subscription_start_date
        schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
          s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
        end
        schedule.next_occurrence.utc.to_i
      end
    end
  end
end
