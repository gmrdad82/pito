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
            bg: Color::Rgb(26, 27, 38),
            fg: Color::Rgb(192, 202, 245),
            border: Color::Rgb(41, 46, 66),
            muted: Color::Rgb(86, 95, 137),
            accent: Color::Rgb(122, 162, 247),
            success: Color::Rgb(158, 206, 106),
            danger: Color::Rgb(247, 118, 142),
            orange: Color::Rgb(255, 158, 100),
            cyan: Color::Rgb(26, 188, 156),
        }
    }

    fn light() -> Self {
        Self {
            bg: Color::Rgb(217, 219, 235),
            fg: Color::Rgb(86, 95, 137),
            border: Color::Rgb(203, 207, 226),
            muted: Color::Rgb(150, 158, 191),
            accent: Color::Rgb(52, 84, 163),
            success: Color::Rgb(72, 140, 86),
            danger: Color::Rgb(197, 59, 83),
            orange: Color::Rgb(182, 101, 51),
            cyan: Color::Rgb(15, 128, 108),
        }
    }
}
