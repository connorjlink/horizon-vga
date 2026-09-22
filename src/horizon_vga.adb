with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Integer_Text_IO;

procedure Horizon_Vga is
   use Ada.Text_IO;
   use Ada.Strings.Unbounded;

   --  R4B4G4A4 color type: 4 bits per channel
   type Color_RGBA is record
      R : Natural range 0 .. 15;
      G : Natural range 0 .. 15;
      B : Natural range 0 .. 15;
      A : Natural range 0 .. 15;
   end record;

   type Framebuffer is array (Natural range <>, Natural range <>) of Color_RGBA;
   type Framebuffer_Access is access all Framebuffer;

   --  optional utility to parse the Stratus C MMIO header
   procedure Parse_Header (Filename : String; Width, Height : out Natural) is
      File     : File_Type;
      Line     : Unbounded_String;
      Position : Natural;
   begin
      Width  := 0;
      Height := 0;

      Open (File, In_File, Filename);

      while not End_Of_File (File) loop
         Line := To_Unbounded_String (Get_Line (File));

         if Index (Line, "FRAMEBUFFER_WIDTH") > 0 then
            Position := Index (Line, "FRAMEBUFFER_WIDTH");
            declare
               Rest      : constant String := Slice (Line, Position + 17, Length (Line));
               Num_Start : Natural := Rest'First;
               Num_End   : Natural;
            begin
               while Num_Start <= Rest'Last and then
                     (Rest (Num_Start) < '0' or else Rest (Num_Start) > '9')
               loop
                  Num_Start := Num_Start + 1;
               end loop;

               if Num_Start <= Rest'Last then
                  Num_End := Num_Start;
                  while Num_End <= Rest'Last and then
                        (Rest (Num_End) >= '0' and then Rest (Num_End) <= '9')
                  loop
                     Num_End := Num_End + 1;
                  end loop;

                  Width := Natural'Value (Rest (Num_Start .. Num_End - 1));
               end if;
            end;
         end if;

         if Index (Line, "FRAMEBUFFER_HEIGHT") > 0 then
            Position := Index (Line, "FRAMEBUFFER_HEIGHT");
            declare
               Rest      : constant String := Slice (Line, Position + 18, Length (Line));
               Num_Start : Natural := Rest'First;
               Num_End   : Natural;
            begin
               while Num_Start <= Rest'Last and then
                     (Rest (Num_Start) < '0' or else Rest (Num_Start) > '9')
               loop
                  Num_Start := Num_Start + 1;
               end loop;

               if Num_Start <= Rest'Last then
                  Num_End := Num_Start;
                  while Num_End <= Rest'Last and then
                        (Rest (Num_End) >= '0' and then Rest (Num_End) <= '9')
                  loop
                     Num_End := Num_End + 1;
                  end loop;

                  Height := Natural'Value (Rest (Num_Start .. Num_End - 1));
               end if;
            end;
         end if;

      end loop;

      Close (File);
   end Parse_Header;

   procedure Write_PPM (Filename : String; FB : Framebuffer) is
      Output : File_Type;
      Height : Natural := FB'Last (1) - FB'First (1) + 1;
      Width  : Natural := FB'Last (2) - FB'First (2) + 1;
   begin
      Create (Output, Out_File, Filename);

      --  PPM header: P6 binary, max color depth 15
      Put_Line (Output, "P6");
      Put_Line (Output, Width'Image & Height'Image);
      Put_Line (Output, "15");

      for Y in FB'Range (1) loop
         for X in FB'Range (2) loop
            declare
               Pixel  : Color_RGBA := FB (Y, X);
               R_Byte : Character := Character'Val (Pixel.R);
               G_Byte : Character := Character'Val (Pixel.G);
               B_Byte : Character := Character'Val (Pixel.B);
            begin
               Put (Output, R_Byte);
               Put (Output, G_Byte);
               Put (Output, B_Byte);
            end;

         end loop;

      end loop;

      Close (Output);
      Put_Line ("PPM file written: " & Filename);
   end Write_PPM;

   function Next_Token (Line : String; Position : in out Natural)
     return String
   is
      Start : Natural;
   begin
      while Position <= Line'Last
        and then (Line (Position) = ' '
        or else Line (Position) = Character'Val (9))
      loop
         Position := Position + 1;
      end loop;

      if Position > Line'Last then
         return "";
      end if;

      Start := Position;
      while Position <= Line'Last and then
         Line (Position) /= ' ' and then
         Line (Position) /= Character'Val (9)
      loop
         Position := Position + 1;
      end loop;

      return Line (Start .. Position - 1);
   end Next_Token;

   function Binary_Value (Bits : String; Valid : out Boolean) return Natural is
      Value : Natural := 0;
   begin
      Valid := Bits'Length > 0;

      for Bit of Bits loop
         if Bit = '0' then
            Value := Value * 2;
         elsif Bit = '1' then
            Value := Value * 2 + 1;
         else
            Valid := False;
            return 0;
         end if;
      end loop;

      return Value;
   end Binary_Value;

   procedure Parse_Trace (Filename : String; FB : in out Framebuffer) is
      File       : File_Type;
      Line       : String (1 .. 1024);
      Line_Length : Natural;
      Position   : Natural;
      Colon      : Natural;
      X          : Natural := FB'First (2);
      Y          : Natural := FB'First (1);
   begin
      Open (File, In_File, Filename);

      while not End_Of_File (File) loop
         Get_Line (File, Line, Line_Length);
         Colon := 0;

         for I in 1 .. Line_Length loop
            if Line (I) = ':' then
               Colon := I;
               exit;
            end if;
         end loop;

         if Colon > 0 and then Colon < Line_Length then
            Position := Colon + 1;

            declare
               HSync : constant String := Next_Token (Line (1 .. Line_Length), Position);
               VSync : constant String := Next_Token (Line (1 .. Line_Length), Position);
               Red   : constant String := Next_Token (Line (1 .. Line_Length), Position);
               Green : constant String := Next_Token (Line (1 .. Line_Length), Position);
               Blue  : constant String := Next_Token (Line (1 .. Line_Length), Position);
               Red_Valid   : Boolean;
               Green_Valid : Boolean;
               Blue_Valid  : Boolean;
               Red_Value   : Natural;
               Green_Value : Natural;
               Blue_Value  : Natural;
            begin
               if HSync = "1" and then VSync = "1" then
                  Red_Value := Binary_Value (Red, Red_Valid);
                  Green_Value := Binary_Value (Green, Green_Valid);
                  Blue_Value := Binary_Value (Blue, Blue_Valid);

                  if Red_Valid and then Green_Valid and then Blue_Valid then
                     FB (Y, X) :=
                       (R => Red_Value, G => Green_Value, B => Blue_Value, A => 15);
                  end if;

                  if X = FB'Last (2) then
                     X := FB'First (2);
                     if Y < FB'Last (1) then
                        Y := Y + 1;
                     end if;
                  else
                     X := X + 1;
                  end if;
               elsif VSync = "0" then
                  Y := FB'First (1);
                  X := FB'First (2);
               elsif HSync = "0" then
                  X := FB'First (2);
               end if;
            end;
         end if;
      end loop;

      Close (File);
   end Parse_Trace;

   Width  : Natural;
   Height : Natural;
   FB     : Framebuffer_Access;
   Trace_Filename : Unbounded_String;

begin
   if Ada.Command_Line.Argument_Count < 1 then
      Put_Line ("Usage: framebuffer_ppm <header_file> [trace_file]");
      return;
   end if;

   Parse_Header (Ada.Command_Line.Argument (1), Width, Height);

   if Width = 0 or Height = 0 then
      Width  := 640;
      Height := 480;
   end if;

   Put_Line ("Framebuffer dimensions: " & Width'Image & " x" & Height'Image);

   FB := new Framebuffer (1 .. Height, 1 .. Width);

   --  initialize framebuffer to black
   for Y in 1 .. Height loop
      for X in 1 .. Width loop
         FB (Y, X) := (R => 0, G => 0, B => 0, A => 15);
      end loop;
   end loop;

   if Ada.Command_Line.Argument_Count >= 2 then
      Trace_Filename :=
        To_Unbounded_String (Ada.Command_Line.Argument (2));
   else
      Trace_Filename := To_Unbounded_String (Ada.Command_Line.Argument (1));
   end if;

   Parse_Trace (To_String (Trace_Filename), FB.all);
   Write_PPM (Ada.Directories.Base_Name (To_String (Trace_Filename)) & ".ppm", FB.all);

end Horizon_Vga;
