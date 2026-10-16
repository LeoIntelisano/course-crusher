"""Open time windows between busy calendar blocks.

Every datetime here must be timezone-aware. Google reports busy periods in UTC
while a student's day is bounded in local time, and comparing naive with aware
values either raises or silently shifts a slot by hours.
"""

import from datetime { date, datetime, time, tzinfo }

glob DEFAULT_MIN_SLOT_MINUTES: int = 15;
glob SECONDS_PER_MINUTE: int = 60;

"""A period when the student is unavailable. `start` is inclusive, `end` exclusive."""
obj BusyBlock {
    has start: datetime;
    has end: datetime;
}

"""An open window the scheduling engine can place work into."""
obj TimeSlot {
    has start_time: datetime;
    has end_time: datetime;
    has duration_minutes: int;
}

def time_slot(start_time: datetime, end_time: datetime) -> TimeSlot {
    seconds = (end_time - start_time).total_seconds();
    return TimeSlot(
        start_time=start_time,
        end_time=end_time,
        duration_minutes=int(seconds // SECONDS_PER_MINUTE)
    );
}

"""Serialize a slot to the JSON contract: ISO 8601 strings with UTC offsets."""
def slot_to_dict(slot: TimeSlot) -> dict[str, str | int] {
    return {
        "start_time": slot.start_time.isoformat(),
        "end_time": slot.end_time.isoformat(),
        "duration_minutes": slot.duration_minutes
    };
}

def require_aware(value: datetime, label: str) {
    if value.tzinfo is None or value.utcoffset() is None {
        raise ValueError(f"{label} must be timezone-aware, got {value.isoformat()}");
    }
}

def require_window(window_start: datetime, window_end: datetime) {
    require_aware(window_start, "window_start");
    require_aware(window_end, "window_end");
    if window_end <= window_start {
        raise ValueError("window_end must be after window_start");
    }
}

"""The local [day_start, day_end) bounds of `day` in `tz`."""
def day_window(day: date, tz: tzinfo, day_start: time, day_end: time) -> tuple[datetime, datetime] {
    if day_end <= day_start {
        raise ValueError("day_end must be after day_start");
    }
    return (
        datetime.combine(day, day_start, tzinfo=tz),
        datetime.combine(day, day_end, tzinfo=tz)
    );
}

"""Sort blocks and collapse any that overlap or touch into a single span."""
def merge_busy_blocks(blocks: list[BusyBlock]) -> list[BusyBlock] {
    merged: list[BusyBlock] = [];
    for block in sorted(blocks, key=lambda (b: BusyBlock) -> datetime { return b.start; }) {
        if merged and block.start <= merged[-1].end {
            last = merged[-1];
            merged = merged[:-1] + [BusyBlock(start=last.start, end=max(last.end, block.end))];
        } else {
            merged = merged + [block];
        }
    }
    return merged;
}

"""Trim blocks to the window and convert them to its zone.

Without the conversion a slot bounded by a UTC busy block on one side and the
local window edge on the other would serialize with two different offsets.
"""
def clip_to_window(
    blocks: list[BusyBlock], window_start: datetime, window_end: datetime
) -> list[BusyBlock] {
    zone = window_start.tzinfo;
    return [
        BusyBlock(
            start=max(b.start, window_start).astimezone(zone),
            end=min(b.end, window_end).astimezone(zone)
        )
        for b in blocks
        if b.end > window_start and b.start < window_end
    ];
}

"""Open windows inside [window_start, window_end) not covered by any busy block.

Blocks may arrive unsorted, overlapping, or from several calendars. Gaps shorter
than `min_duration_minutes` are dropped: a 5-minute hole between classes is
travel time, not a work session.
"""
def find_free_slots(
    busy: list[BusyBlock],
    window_start: datetime,
    window_end: datetime,
    min_duration_minutes: int = DEFAULT_MIN_SLOT_MINUTES
) -> list[TimeSlot] {
    require_window(window_start, window_end);
    if min_duration_minutes < 1 {
        raise ValueError("min_duration_minutes must be at least 1");
    }
    for block in busy {
        require_aware(block.start, "busy block start");
        require_aware(block.end, "busy block end");
        if block.end < block.start {
            raise ValueError(f"Busy block ends before it starts: {block.start.isoformat()}");
        }
    }
    merged = merge_busy_blocks(clip_to_window(busy, window_start, window_end));
    gap_starts = [window_start] + [b.end for b in merged];
    gap_ends = [b.start for b in merged] + [window_end];
    return [
        slot
        for slot in [time_slot(s, e) for (s, e) in zip(gap_starts, gap_ends, strict=True)]
        if slot.duration_minutes >= min_duration_minutes
    ];
}
