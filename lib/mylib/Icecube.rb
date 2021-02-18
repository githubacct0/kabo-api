# frozen_string_literal: true

module MyLib
  class Icecube
    class << self
      # Upcoming billing date
      def subscription_start_date(date_time = "2020-01-03 12:00:00", week = 2)
        schedule = subscription_schedule(date_time, week)
        schedule.next_occurrence.utc.to_i
      end

      # Next occurrencies
      def subscription_next_occurrencies(date_time = "2020-01-03 09:00:00", week = 2)
        schedule = subscription_schedule(date_time, week)
        schedule.next_occurrences(4, Time.now).map { |_week| _week.strftime("%B %e") }
      end

      # Get schedule
      def subscription_schedule(date_time, week)
        schedule = IceCube::Schedule.new(Time.zone.parse(date_time)) do |s|
          s.add_recurrence_rule IceCube::Rule.weekly(week).day(:friday)
        end

        schedule
      end
    end
  end
end
