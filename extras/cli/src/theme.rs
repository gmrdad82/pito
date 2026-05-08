use ratatui::style::Color;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThemeMode {
    Dark,
    Light,
}

impl ThemeMode {
    pub fn toggle(self) -> Self {
        match self {
            Self::Dark => Self::Light,
            Self::Light => Self::Dark,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct Theme {
    pub bg: Color,
    pub fg: Color,
    pub border: Color,
    pub muted: Color,
    pub accent: Color,
    pub success: Color,
    pub danger: Color,
    pub orange: Color,
    pub cyan: Color,
}

impl Theme {
    pub fn from_mode(mode: ThemeMode) -> Self {
        match mode {
            ThemeMode::Dark => Self::dark(),
            ThemeMode::Light => Self::light(),
        }
    }

    fn dark() -> Self {
        Self {
            bg: Color::Rgb(40, 42, 54),
            fg: Color::Rgb(248, 248, 242),
            border: Color::Rgb(68, 71, 90),
            muted: Color::Rgb(98, 114, 164),
            accent: Color::Rgb(189, 147, 249),
            success: Color::Rgb(80, 250, 123),
            danger: Color::Rgb(255, 85, 85),
            orange: Color::Rgb(255, 184, 108),
            cyan: Color::Rgb(139, 233, 253),
        }
    }

    fn light() -> Self {
        Self {
            bg: Color::Rgb(248, 248, 242),
            fg: Color::Rgb(40, 42, 54),
            border: Color::Rgb(200, 200, 210),
            muted: Color::Rgb(120, 120, 140),
            accent: Color::Rgb(130, 80, 200),
            success: Color::Rgb(30, 150, 60),
            danger: Color::Rgb(200, 50, 50),
            orange: Color::Rgb(200, 130, 50),
            cyan: Color::Rgb(50, 150, 180),
        }
    }
}
