with Ada.Text_IO;
with Ada.Command_Line;
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

   Width  : Natural;
   Height : Natural;
   FB     : Framebuffer_Access;

begin
   if Ada.Command_Line.Argument_Count < 1 then
      Put_Line ("Usage: framebuffer_ppm <header_file>");
      return;
   end if;

   Parse_Header (Ada.Command_Line.Argument (1), Width, Height);

   if Width = 0 or Height = 0 then
      Width  := 640;
      Height := 480;
   end if;

   Put_Line ("Framebuffer dimensions: " & Width'Image & " x" & Height'Image);

   FB := new Framebuffer (1 .. Height, 1 .. Width);

   --  TODO: fill in real logic here
   for Y in 1 .. Height loop
      for X in 1 .. Width loop
         FB (Y, X) := (R => Natural(Float(X) / Float(Width) * 15.0), G => Natural(Float(Y) / Float(Height) * 15.0), B => 0, A => 15);
      end loop;
   end loop;

   Write_PPM ("output.ppm", FB.all);

end Horizon_Vga;
