def matchers -> list[CourseMatcher] {
    return [
        course_matcher("EECS 445", "Machine Learning", ["ML"]),
        course_matcher("PHYS 240", "", ["Physics lab"]),
        course_matcher("COMM 261", "Views on the News", [])
    ];
}

test "normalize keeps letters and digits only" {
    assert normalize("  EECS-445: Lecture!! ") == "eecs 445 lecture";
    assert normalize("") == "";
}

test "codes match with or without the space" {
    assert match_course("EECS 445 Lecture", matchers()) == "EECS 445";
    assert match_course("eecs445 lec", matchers()) == "EECS 445";
    assert match_course("[EECS-445] Office Hours", matchers()) == "EECS 445";
}

test "course names and tags match as whole words" {
    assert match_course("Machine Learning discussion", matchers()) == "EECS 445";
    assert match_course("ML study group", matchers()) == "EECS 445";
    assert match_course("HTML workshop", matchers()) == "";
    assert match_course("Physics lab writeup", matchers()) == "PHYS 240";
}

test "numbers must match whole tokens" {
    assert match_course("EECS 4450 seminar", matchers()) == "";
    assert match_course("PHYS 2400", matchers()) == "";
}

test "the longest matching phrase wins" {
    tagged = [course_matcher("EECS 445", "", []), course_matcher("CHEM 125", "", ["lab"])];
    assert match_course("EECS 445 lab", tagged) == "EECS 445";
    assert match_course("Lab cleanup", tagged) == "CHEM 125";
}

test "short course names are not used as phrases" {
    short = course_matcher("ART 101", "Art", []);
    assert short.phrases == ["art 101", "art101"];
}

test "unrelated events match nothing" {
    assert match_course("Dentist", matchers()) == "";
    assert match_course("", matchers()) == "";
    assert match_course("EECS 445", []) == "";
}

test "event kinds come from common words" {
    assert event_kind("EECS 445 Lecture") == "Lecture";
    assert event_kind("PHYS 240 Lab") == "Lab";
    assert event_kind("EECS 445 Midterm") == "Exam";
    assert event_kind("Prof. Ramirez office hours") == "Office hours";
    assert event_kind("EECS 376 Discussion 012") == "Discussion";
    assert event_kind("Dinner with Sam") == "";
    assert event_kind("Labor Day") == "";
}
